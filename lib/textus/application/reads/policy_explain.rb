module Textus
  module Application
    module Reads
      # For one key, surface every matching policy block along with the
      # per-slot effective value (which loses ties win-by-specificity).
      class PolicyExplain
        def initialize(ctx:)
          @ctx = ctx
        end

        def call(key:)
          policies = @ctx.store.manifest.rules
          matching = policies.explain(key)
          winners  = policies.for(key)

          {
            key: key,
            matched_blocks: matching.map do |b|
              {
                match: b.match,
                refresh: !b.refresh.nil?,
                handler_allowlist: !b.handler_allowlist.nil?,
                promote: !b.promote.nil?,
              }
            end,
            effective: {
              refresh: winners.refresh && {
                ttl_seconds: winners.refresh.ttl_seconds,
                on_stale: winners.refresh.on_stale,
              },
              handler_allowlist: winners.handler_allowlist&.handlers,
              promotion: winners.promote && { requires: winners.promote.requires },
            },
          }
        end
      end
    end
  end
end
