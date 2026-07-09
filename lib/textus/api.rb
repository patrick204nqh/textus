module Textus
  class API
    def initialize(gate:, store:)
      @gate = gate
      @store = store
      @session_store = Protocol::SessionStore.new(@store.container.store.db)
      @workspace = Workspace.new(@store)
    end

    # ── Session lifecycle ──

    def open_session(role:)
      slug = "#{('a'..'z').to_a.sample}#{SecureRandom.hex(4)}"
      sid = @session_store.create(
        id: "#{Time.now.utc.strftime("%Y-%m-%d")}-#{slug}",
        role:, surface_id: nil,
      )[:id]
      @workspace.create(sid, role:)
      session = Session.new(id: sid, role:)
      loop_for(session).first if role == "agent"
      session
    end

    def resume_session(id:)
      row = @session_store.find(id)
      raise UsageError.new("session not found: #{id}") unless row
      Session.new(id: row[:id], role: row[:role],
                  correlation_id: row[:correlation_id], payload: row[:payload])
    end

    def close_session(session, nodes_checked: nil)
      @session_store.seal(session.id)
      @workspace.close(session.id, loop_status: session.payload["loop"], nodes_checked:) if session.agent?
    end

    # ── Loop ──

    def loop_for(session)
      Loop.new(loop_node_names, store: @session_store, session:, gate: @gate)
    end

    # ── Dispatch ──

    def get(key:, session:)          = dispatch(:get, session:, key:)
    def put(key:, data:, session:, **opts) = dispatch(:put, session:, key:, data:, **opts)
    def list(session:, **opts)        = dispatch(:list, session:, **opts)
    def propose(key:, data:, session:, **opts) = dispatch(:propose, session:, key:, data:, **opts)
    def accept(pending_key:, session:) = dispatch(:accept, session:, pending_key:)
    def reject(pending_key:, session:, **opts) = dispatch(:reject, session:, pending_key:, **opts)
    def audit(session:, **filters)    = dispatch(:audit, session:, **filters)
    def blame(key:, session:, **opts) = dispatch(:blame, session:, key:, **opts)
    def deps(key:, session:)          = dispatch(:deps, session:, key:)
    def graph(key:, session:, **opts)  = dispatch(:graph, session:, key:, **opts)
    def uid(key:, session:)           = dispatch(:uid, session:, key:)
    def where(key:, session:)         = dispatch(:where, session:, key:)
    def rdeps(key:, session:)         = dispatch(:rdeps, session:, key:)
    def pulse(session:, **opts)       = dispatch(:pulse, session:, **opts)
    def drain(session:, **opts)       = dispatch(:drain, session:, **opts)
    def schema_list(session:)         = dispatch(:schema_list, session:)
    def schema_show(key:, session:)   = dispatch(:schema_show, session:, key:)
    def key_delete(key:, session:, **opts) = dispatch(:key_delete, session:, key:, **opts)
    def key_mv(from:, to:, session:, **opts) = dispatch(:key_mv, session:, from:, to:, **opts)
    def ingest(kind:, slug:, session:, **opts) = dispatch(:ingest, session:, kind:, slug:, **opts)
    def blueprint(key:, session:)     = dispatch(:blueprint, session:, key:)
    def data_mv(from:, to:, session:, **opts) = dispatch(:data_mv, session:, from:, to:, **opts)
    def key_mv_under(from_under:, to_under:, session:, **opts) = dispatch(:key_mv_under, session:, from_under:, to_under:, **opts)
    def key_delete_under(under:, session:, **opts) = dispatch(:key_delete_under, session:, under:, **opts)
    def session_open(session:, **opts) = dispatch(:session_open, session:, **opts)
    def session_close(session_id:, session:, **opts) = dispatch(:session_close, session:, session_id:, **opts)
    def diff(pending_key:, session:)  = dispatch(:diff, session:, pending_key:)

    def boot(**)
      Protocol::Boot.build(container: @store.container)
    end

    def cursor(**)
      @store.store.audit_log.latest[:seq]
    end

    private

    def dispatch(action, session:, **params)
      request = Adapters::Request.new(
        action:, params:, role: session.role,
        session_id: session.id, correlation_id: session.correlation_id,
      )
      response = @gate.dispatch(request)
      raise response.error if response.error
      response.payload
    end

    def loop_node_names
      @store.manifest.data.entries
        .select { |e| e.key.start_with?("knowledge.loop.") && e.key.count(".") == 2 }
        .map { |e| e.key.split(".").last.to_sym }
    end
  end
end
