module Textus
  module Protocol
    class Gate
      def initialize(manifest:, resolver:, async: nil)
        @manifest = manifest
        @resolver = resolver
        @async = async
      end

      def dispatch(role, verb, params = {})
        key = params[:key]
        authorize!(role, verb, key)

        if key
          resolution = @resolver.resolve(key)
          return error(:not_found, "Key not found: #{key}") unless resolution
        end

        { ok: true, verb:, role:, key: }
      end

      private

      def authorize!(role, verb, key)
        return true if %i[boot pulse].include?(verb)
        return true if role == :automation && verb == :drain

        if key
          lane = key.split(".").first
          writers = @manifest.data.lanes[lane]&.dig(:writers) || []
          allowed = writers.map(&:to_sym).include?(role)
          raise Textus::AuthError.new("#{role} cannot #{verb} on #{key}") unless allowed
        end

        true
      end

      def error(code, message)
        { error: { code: code.to_s, message: } }
      end
    end
  end
end
