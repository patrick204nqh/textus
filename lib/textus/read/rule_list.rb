module Textus
  module Read
    # Enumerate every declared rule block in the manifest, in order. This is
    # the whole-manifest view; `rule_explain` is the for-key view. Extracted
    # from the CLI verb so the rule family is fully use-case-backed (ADR 0059);
    # CLI-only (no MCP contract) — an agent reasons per-key via rule_explain.
    class RuleList
      extend Textus::Contract::DSL

      verb     :rule_list
      summary  "List every rule block in the manifest."
      surfaces :cli
      cli      "rule list"
      view(:cli) { |policies| { "verb" => "rule_list", "policies" => policies } }

      def initialize(container:, call: nil) # rubocop:disable Lint/UnusedMethodArgument
        @manifest = container.manifest
      end

      def call
        @manifest.rules.blocks.map do |b|
          row = { "match" => b.match }
          if b.lifecycle
            row["lifecycle"] = {
              "ttl_seconds" => b.lifecycle.ttl_seconds,
              "on_expire" => b.lifecycle.on_expire,
              "budget_ms" => b.lifecycle.budget_ms,
            }
          end
          row["handler_allowlist"] = b.handler_allowlist.handlers if b.handler_allowlist
          row["guard"] = b.guard if b.guard
          row
        end
      end
    end
  end
end
