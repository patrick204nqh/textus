module Textus
  module Protocol
    class Gate
      AUTHOR_ACTIONS = %i[accept reject].to_set.freeze

      attr_writer :container

      HANDLER_GROUPS = {
        read: Handlers::Read,
        write: Handlers::Write,
        maintenance: Handlers::System,
      }.freeze

      def initialize(store_engine:, container: nil, store_resolver: StoreResolver, session_store: nil, default_role: "agent")
        @store_engine = store_engine
        @container = container
        @store_resolver = store_resolver
        @session_store = session_store
        @default_role = default_role
      end

      def dispatch(request, env: ENV, cwd: Dir.pwd)
        raise Textus::UsageError.new("Request expected") unless request.is_a?(Protocol::Message::Request)

        spec = ActionRegistry.for(request.action)
        raise Textus::UsageError.new("unknown action: #{request.action}") unless spec

        role = request.role || @default_role
        authorize!(role, request.params[:key], spec)

        session = resolve_session(request.session_id, role)
        cid = request.correlation_id || session[:id]
        call_obj = Value::Call.build(role:, correlation_id: cid)

        bound = Binder.bind(spec, request.params)
        ctx_class = spec.read? && !spec.system? ? Handlers::QueryContext : Handlers::CommandContext
        ctx = ctx_class.new(@store_engine, @container, call_obj)

        handler = spec.lane ? Lane.handler_for(spec.lane) : handler_group(spec)
        result = handler.public_send(request.action, **bound, ctx:, call: call_obj)

        persist_session(session, spec) if spec.write?
        Protocol::Message::Response.new(payload: result, error: nil)
      rescue Textus::Error => e
        Protocol::Message::Response.new(payload: nil, error: e)
      end

      private

      def resolve_session(session_id, role)
        if session_id
          row = @session_store&.find(session_id)
          return row if row
        end
        create_session(role)
      end

      def create_session(role)
        sid = "#{Time.now.utc.strftime("%Y-%m-%d")}-#{SecureRandom.hex(4)}"
        @session_store&.create(id: sid, role:, surface_id: "gate", expires_at: Time.now.utc + 86400)
        write_scratchpad_session(sid, role)
        { id: sid, role:, cursor_seq: 0 }
      end

      def write_scratchpad_session(sid, role)
        return unless @container

        key = "scratchpad.sessions.#{sid}"
        content = {
          "session_id" => sid, "role" => role,
          "created_at" => Time.now.utc.iso8601, "status" => "active",
        }
        call_obj = Textus::Value::Call.build(role:, correlation_id: sid)
        ctx = Handlers::CommandContext.new(@store_engine, @container, call_obj)
        ctx.put(key:, meta: {}, body: JSON.generate(content), content: nil, call: call_obj)
      rescue Exception => e
        warn("textus: failed to write scratchpad session #{sid}: #{e.message}")
      end

      def persist_session(session, spec)
        return unless @session_store

        seq = @container.store.audit_log.latest[:seq]
        etag = Value::Etag.for_contract(@container.layout)
        @session_store.save(session[:id], cursor_seq: seq, contract_etag: etag.to_s)
      end

      def handler_group(spec)
        spec.system? ? Handlers::System : (HANDLER_GROUPS[spec.category] || Handlers::System)
      end

      def authorize!(role, key, spec)
        return true unless spec&.write?

        check_author_action!(role, spec.action)

        lane_name = key&.split(".")&.first || spec.lane&.to_s
        return true unless lane_name && Textus::Protocol::V4::LANES[lane_name]

        @container.manifest.policy.allowed!(role:, lane: lane_name, key:)
      end

      def check_author_action!(role, action)
        return unless AUTHOR_ACTIONS.include?(action)

        author_writers = @container.manifest.policy.writers_for("knowledge")
        return if author_writers.map(&:to_sym).include?(role.to_sym)

        raise Textus::WriteForbidden.new(
          action, "scratchpad",
          verb: action.to_s, holders: author_writers
        )
      end
    end
  end
end
