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
        authorize!(role, verb, key)

        if spec.lane
          dispatch_to_lane(role, verb, spec, params, call)
        else
          dispatch_via_pipeline(role, verb, spec, params, call)
        end
      end

      private

      def dispatch_to_lane(role, verb, spec, params, call)
        bound = Dispatch::Binder.inputs_from_wire(spec, params)
        handler = Lane.handler_for(spec.lane)
        call_obj = call || Value::Call.build(role:, correlation_id: SecureRandom.uuid)
        result = handler.public_send(verb, **bound, container: @pipeline.container, call: call_obj)
        Value::Result.extract(Value::Result.success(result))
      rescue Textus::Error => e
        Value::Result.failure(e.code, e.message, details: e.details)
      end

      def dispatch_via_pipeline(role, verb, spec, params, call)
        pending = Dispatch::Binder.command(spec, params)
        call_obj = call || Value::Call.build(role:, correlation_id: SecureRandom.uuid)
        result = @pipeline.dispatch(pending, call: call_obj)
        Value::Result.extract(result)
      end

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
