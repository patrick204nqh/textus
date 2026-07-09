module Textus
  module Adapters
    class McpAdapter
      def match?(raw)
        raw.is_a?(Hash) && raw.key?("method")
      end

      def normalize(raw)
        Request.new(
          verb: raw["method"].to_s.to_sym,
          params: (raw["params"] || {}).transform_keys(&:to_sym),
          role: raw["role"],
          session_id: raw["session_id"],
        )
      end
    end
  end
end
