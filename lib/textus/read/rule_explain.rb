module Textus
  module Read
    # Effective rules for a key, at two depths (ADR 0059). Lean by default —
    # `{ lifecycle, guard }`, the agent-cheap read that was the `rules` verb. With
    # `detail: true` it returns the verbose explanation — every matching policy
    # block plus the per-transition guard predicate names — that was
    # `policy_explain`. One verb, one name across CLI/MCP/method; the audience
    # split is a parameter, not two tools.
    class RuleExplain
      extend Textus::Contract::DSL

      verb     :rule_explain
      summary  "Effective rules for a key. Lean {lifecycle, guard} by default; detail: true adds matched blocks + guard predicates."
      surfaces :cli, :mcp
      cli      "rule explain"
      arg :key,    String, required: true, positional: true,
                           description: "dotted key whose effective rules you want (lifecycle ttl/action, write guard, ...)"
      arg :detail, :boolean,
          description: "defaults false: lean {lifecycle, guard}. detail: true adds matched blocks + guard predicates per transition."
      view(:cli) { |r| { "verb" => "rule_explain" }.merge(r.transform_keys(&:to_s)) }

      def initialize(container:, call: nil) # rubocop:disable Lint/UnusedMethodArgument
        @manifest = container.manifest
        @schemas  = container.schemas
      end

      REGISTRY = Textus::Manifest::Schema::FIELD_REGISTRY
      # Field membership is registry-driven (WS3). Lean shows the fields tagged
      # for :lean; detail's matched_blocks flag every :detail field. The
      # `effective` value-block shows the instantiated-policy fields (those with
      # a policy_class) — guard, being a raw deferred field, is surfaced through
      # the dedicated `guards:` predicate section instead.
      LEAN_FIELDS    = REGISTRY.select { |_, m| m[:in_rule_explain].include?(:lean) }.keys.freeze
      DETAIL_FIELDS  = REGISTRY.select { |_, m| m[:in_rule_explain].include?(:detail) }.keys.freeze
      EFFECTIVE_FIELDS = DETAIL_FIELDS.select { |f| REGISTRY[f][:policy_class] }.freeze

      def call(key, detail: false)
        detail ? explain(key) : effective(key)
      end

      private

      # Lean: the effective winners only (formerly Read::Rules / the `rules` verb).
      def effective(key)
        set = @manifest.rules.for(key)
        LEAN_FIELDS.each_with_object({}) do |field, out|
          value = set.public_send(field)
          out[field.to_s] = lean_value(field, value) unless value.nil?
        end
      end

      def lean_value(field, value)
        case field
        when :retention then retention_hash(value, string_keys: true)
        else value
        end
      end

      # Verbose: every matching block, per-slot effective value, and the
      # effective guard predicate names for each write transition (formerly
      # Read::PolicyExplain, ADR 0031).
      def explain(key)
        matching = @manifest.rules.explain(key)
        winners  = @manifest.rules.for(key)
        factory  = Textus::Domain::Policy::GuardFactory.new(manifest: @manifest, schemas: @schemas)

        {
          key: key,
          matched_blocks: matching.map do |b|
            { match: b.match }.merge(DETAIL_FIELDS.to_h { |f| [f, !b.public_send(f).nil?] })
          end,
          effective: EFFECTIVE_FIELDS.to_h { |f| [f, effective_value(f, winners.public_send(f))] },
          guards: Textus::Domain::Policy::BaseGuards::BASE.keys.to_h do |transition|
            [transition, factory.for(transition, key).predicates.map(&:name)]
          end,
        }
      end

      def effective_value(field, value)
        return nil if value.nil?

        case field
        when :retention         then retention_hash(value, string_keys: false)
        when :handler_allowlist then value.handlers
        else value
        end
      end

      # ADR 0093: retention is a flat GC policy (ttl + drop/archive action).
      def retention_hash(retention, string_keys:)
        h = { ttl_seconds: retention.ttl_seconds, action: retention.action }
        string_keys ? h.transform_keys(&:to_s) : h
      end
    end
  end
end
