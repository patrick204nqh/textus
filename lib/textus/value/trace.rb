module Textus
  module Value
    Trace = Data.define(:verb, :duration_ms, :correlation_id, :role, :key, :error) do
      def self.record(verb:, duration_ms:, correlation_id:, role:, key: nil, error: nil)
        new(verb:, duration_ms:, correlation_id:, role:, key:, error:)
      end

      def success? = error.nil?

      def to_h_for_wire
        h = { "verb" => verb.to_s, "duration_ms" => duration_ms, "correlation_id" => correlation_id }
        h["role"] = role if role
        h["key"] = key if key
        h["error"] = error if error
        h
      end
    end
  end
end
