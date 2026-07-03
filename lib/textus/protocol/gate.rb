module Textus
  module Protocol
    class Gate


      def initialize(manifest:, resolver:, pipeline:, async: nil)
        @manifest = manifest
        @resolver = resolver
        @pipeline = pipeline
        @async = async
      end

      def dispatch(role, verb, params = {}, call: nil)
        spec = VerbRegistry.for(verb)
        return error(:unknown_verb, "Unknown verb: #{verb}") unless spec

        key = params[:key]
        authorize!(role, verb, key, spec)

    call_obj = call || Value::Call.build(role:, correlation_id: SecureRandom.uuid)
    bound = Protocol::Binder.bind(spec, params)
    ctx = HandlerContext.new(@pipeline.container)

    handler = spec.lane ? Lane.handler_for(spec.lane) : Protocol::Handlers

    handler.public_send(verb, **bound, ctx:, call: call_obj)
    end

      private

      def authorize!(role, verb, key, spec)
        return true unless spec&.write?

        lane = key&.split(".")&.first || spec.lane&.to_s
        return true unless lane

        zone = Textus::Protocol::V4::LANES[lane]
        return true unless zone

        writers = zone[:writers] || []
        allowed = writers.map(&:to_sym).include?(role)
        raise Textus::WriteForbidden.new(key, lane, holders: writers) unless allowed

        true
      end

      def error(code, message)
        { error: { code: code.to_s, message: } }
      end
    end
  end
end
