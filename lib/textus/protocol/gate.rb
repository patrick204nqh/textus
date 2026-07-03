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
        key = params[:key]
        authorize!(role, verb, key)

        if key
          resolution = @resolver.resolve(key)
          return error(:not_found, "Key not found: #{key}") unless resolution
        end

        spec = VerbRegistry.for(verb)
        return error(:unknown_verb, "Unknown verb: #{verb}") unless spec

        pending = Dispatch::Binder.command(spec, params)
        call_obj = call || Value::Call.build(role: role, correlation_id: SecureRandom.uuid)
        result = @pipeline.dispatch(pending, call: call_obj)
        Value::Result.extract(result)
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
