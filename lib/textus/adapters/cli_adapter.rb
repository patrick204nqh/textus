module Textus
  module Adapters
    class CliAdapter
      def initialize(default_role: "agent")
        @default_role = default_role
      end

      def match?(raw)
        raw.is_a?(Array)
      end

      def normalize(raw)
        role_kv = raw.find { |a| a.start_with?("--as=") }
        non_flag = raw.reject { |a| a.start_with?("--") }
        verb = non_flag.first
        Request.new(
          verb: (verb || "help").to_s.to_sym,
          params: { positionals: non_flag.drop(1) },
          role: role_kv&.delete_prefix("--as=") || @default_role,
        )
      end
    end
  end
end
