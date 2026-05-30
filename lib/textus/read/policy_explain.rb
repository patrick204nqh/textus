module Textus
  module Read
    # For one key, surface every matching policy block along with the
    # per-slot effective value (which loses ties win-by-specificity) and the
    # effective guard predicate names for every write transition (ADR 0031).
    class PolicyExplain
      def initialize(container:, call: nil) # rubocop:disable Lint/UnusedMethodArgument
        @manifest = container.manifest
        @schemas  = container.schemas
      end

      def call(key:)
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
