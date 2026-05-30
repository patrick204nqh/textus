module Textus
  module Read
    # For one key, surface every matching policy block along with the
    # per-slot effective value (which loses ties win-by-specificity).
    class PolicyExplain
      def initialize(container:, call: nil) # rubocop:disable Lint/UnusedMethodArgument
        @manifest = container.manifest
      end

      def call(key:)
        policies = @manifest.rules
        matching = policies.explain(key)
        winners  = policies.for(key)

        {
          key: key,
          matched_blocks: matching.map do |b|
            {
              match: b.match,
              fetch: !b.fetch.nil?,
              handler_allowlist: !b.handler_allowlist.nil?,
              promote: !b.promote.nil?,
              retention: !b.retention.nil?,
            }
          end,
          effective: {
            fetch: winners.fetch && {
              ttl_seconds: winners.fetch.ttl_seconds,
              on_stale: winners.fetch.on_stale,
            },
            handler_allowlist: winners.handler_allowlist&.handlers,
            promotion: winners.promote && { requires: winners.promote.requires },
            retention: winners.retention && {
              expire_after: winners.retention.expire_after,
              archive_after: winners.retention.archive_after,
            },
          },
        }
      end
    end
  end
end
