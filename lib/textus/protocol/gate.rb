module Textus
  module Protocol
    class Gate
      include Builtin

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
        authorize!(role, verb, key)

        call_obj = call || Value::Call.build(role:, correlation_id: SecureRandom.uuid)
        bound = Protocol::Binder.bind(spec, params)

        if spec.lane
          handler = Lane.handler_for(spec.lane)
          result = handler.public_send(verb, **bound, container: @pipeline.container, call: call_obj)
        else
          result = send(:"builtin_#{verb}", **bound, call: call_obj)
        end
        Value::Result.extract(Value::Result.success(result))
      rescue Textus::WriteForbidden
        raise
      rescue Textus::Error => e
        Value::Result.failure(e.code, e.message, details: e.details)
      end

      private

      def authorize!(role, verb, key)
        spec = VerbRegistry.for(verb)
        return true unless spec&.write?

        return true if role == :automation && verb == :drain

        lane = key&.split(".")&.first
        return true unless lane

        writers = Textus::Protocol::V4::LANES.dig(lane, :writers) || []
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
