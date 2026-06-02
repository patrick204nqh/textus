module Textus
  module Read
    # Effective rule set (fetch + guard) for a key. Was the inlined MCP
    # `rules` tool; promoted to a first-class verb so MCP is a pure projection
    # (ADR 0039).
    class Rules
      extend Textus::Contract::DSL

      verb     :rules
      summary  "Return effective rules for a key (fetch, guard, ...)."
      surfaces :ruby, :mcp
      arg :key, String, required: true, positional: true,
                        description: "dotted key whose effective rules you want (fetch ttl/action, write guard, ...)"

      def initialize(container:, call: nil) # rubocop:disable Lint/UnusedMethodArgument
        @manifest = container.manifest
      end

      def call(key)
        set = @manifest.rules.for(key)
        { "fetch" => set.fetch&.to_h, "guard" => set.guard }.compact
      end
    end
  end
end
