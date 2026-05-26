module Textus
  class CLI
    class Verb
      class RuleList < Verb
        def call(store)
          policies = store.manifest.rules.blocks.map do |b|
            row = { "match" => b.match }
            if b.refresh
              row["refresh"] = {
                "ttl_seconds" => b.refresh.ttl_seconds,
                "on_stale" => b.refresh.on_stale,
                "sync_budget_ms" => b.refresh.sync_budget_ms,
                "fetch_timeout_seconds" => b.refresh.fetch_timeout_seconds,
              }
            end
            row["handler_allowlist"] = b.handler_allowlist.handlers if b.handler_allowlist
            row["promotion"] = { "requires" => b.promote.requires } if b.promote
            row["retention"] = b.retention if b.retention
            row
          end
          emit({ "verb" => "policy_list", "policies" => policies })
        end
      end
    end
  end
end
