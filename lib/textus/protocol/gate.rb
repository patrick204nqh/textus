module Textus
  module Protocol
    class Gate
      HANDLER_GROUPS = {
        read: Handlers::Read,
        write: Handlers::Write,
        maintenance: Handlers::System,
      }.freeze

      def initialize(manifest:, resolver:, container:, store_engine:, policy: nil, async: nil)
        @manifest = manifest
        @resolver = resolver
        @container = container
        @store_engine = store_engine
        @async = async
        @policy = policy || manifest.policy
      end

      def dispatch(role, verb, params = {}, call: nil)
        spec = VerbRegistry.for(verb)
        return error(:unknown_verb, "Unknown verb: #{verb}") unless spec

        key = params[:key]
        authorize!(role, verb, key, spec)

        call_obj = call || Value::Call.build(role:, correlation_id: SecureRandom.uuid)
        bound = Protocol::Binder.bind(spec, params)
        ctx = Handlers::Context.new(@container, store_engine: @store_engine, call: call_obj)

        handler = spec.lane ? Lane.handler_for(spec.lane) : handler_group(spec)
        handler.public_send(verb, **bound, ctx:, call: call_obj)
      end

      private

      def handler_group(spec)
        return Handlers::System if spec.system?

        HANDLER_GROUPS[spec.category] || Handlers::System
      end

      def authorize!(role, _verb, key, spec)
        return true unless spec&.write?

        key_lane = key&.split(".")&.first
        lane = key_lane || spec.lane&.to_s
        return true unless lane

        lane_map = Textus::Protocol::V4::LANES[lane]
        return true unless lane_map

        @policy.allowed!(role:, lane:, key:)
      end

      def error(code, message)
        { error: { code: code.to_s, message: } }
      end
    end
  end
end
