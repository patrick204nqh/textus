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

      # Fields shown here are driven by FIELD_REGISTRY (in_rule_list); only the
      # per-field serialization below is field-specific.
      LIST_FIELDS = Textus::Manifest::Schema::FIELD_REGISTRY.select { |_, m| m[:in_rule_list] }.keys.freeze

      def call
        @manifest.rules.blocks.map do |b|
          row = { "match" => b.match }
          LIST_FIELDS.each do |field|
            value = b.public_send(field)
            row[field.to_s] = serialize(field, value) unless value.nil?
          end
          row
        end
      end

      private

      def serialize(field, value)
        case field
        when :upkeep
          serialize_upkeep(value)
        when :handler_allowlist
          value.handlers
        else
          value
        end
      end

      # ADR 0091: grammar is keyed (no `on:` discriminator in rendered output).
      def serialize_upkeep(upkeep)
        if upkeep.stale?
          { "ttl_seconds" => upkeep.lifecycle.ttl_seconds,
            "action" => upkeep.lifecycle.on_expire, "budget_ms" => upkeep.lifecycle.budget_ms }
        else
          { "strategy" => upkeep.materialize.on_change }
        end
      end
    end
  end
end
