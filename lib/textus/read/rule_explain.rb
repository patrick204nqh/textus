module Textus
  module Read
    # Effective rules for a key, at two depths (ADR 0059). Lean by default —
    # `{ fetch, guard }`, the agent-cheap read that was the `rules` verb. With
    # `detail: true` it returns the verbose explanation — every matching policy
    # block plus the per-transition guard predicate names — that was
    # `policy_explain`. One verb, one name across CLI/MCP/method; the audience
    # split is a parameter, not two tools.
    class RuleExplain
      extend Textus::Contract::DSL

      verb     :rule_explain
      summary  "Effective rules for a key. Lean {fetch, guard} by default; detail: true adds matched blocks + guard predicates."
      surfaces :cli, :ruby, :mcp
      cli      "rule explain"
      arg :key,    String, required: true, positional: true,
                           description: "dotted key whose effective rules you want (fetch ttl/action, write guard, ...)"
      arg :detail, :boolean,
          description: "defaults false: lean {fetch, guard}. detail: true adds matched blocks + guard predicates per transition."
      cli_response { |r| { "verb" => "rule_explain" }.merge(r.transform_keys(&:to_s)) }

      def initialize(container:, call: nil) # rubocop:disable Lint/UnusedMethodArgument
        @manifest = container.manifest
        @schemas  = container.schemas
      end

      def call(key, detail: false)
        detail ? explain(key) : effective(key)
      end

      private

      # Lean: the effective winners only (formerly Read::Rules / the `rules` verb).
      def effective(key)
        set = @manifest.rules.for(key)
        {
          "fetch" => set.fetch && {
            "ttl_seconds" => set.fetch.ttl_seconds,
            "on_stale" => set.fetch.on_stale,
            "sync_budget_ms" => set.fetch.sync_budget_ms,
            "fetch_timeout_seconds" => set.fetch.fetch_timeout_seconds,
          },
          "guard" => set.guard,
        }.compact
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
            {
              match: b.match,
              fetch: !b.fetch.nil?,
              handler_allowlist: !b.handler_allowlist.nil?,
              guard: !b.guard.nil?,
              retention: !b.retention.nil?,
            }
          end,
          effective: {
            fetch: winners.fetch && {
              ttl_seconds: winners.fetch.ttl_seconds,
              on_stale: winners.fetch.on_stale,
            },
            handler_allowlist: winners.handler_allowlist&.handlers,
            retention: winners.retention && {
              expire_after: winners.retention.expire_after,
              archive_after: winners.retention.archive_after,
            },
          },
          guards: Textus::Domain::Policy::BaseGuards::BASE.keys.to_h do |transition|
            [transition, factory.for(transition, key).predicates.map(&:name)]
          end,
        }
      end
    end
  end
end
