module Textus
  module Adapters
    class WebAdapter
      def match?(raw)
        raw.is_a?(Hash) && raw.key?("verb")
      end

      def normalize(raw)
        verb = raw.delete("verb").to_s.to_sym
        role = raw.delete("role")&.to_s
        session_id = raw.delete("session_id")
        Request.new(verb:, params: raw.transform_keys(&:to_sym), role:, session_id:)
      end
    end
  end
end
