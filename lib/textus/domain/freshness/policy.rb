module Textus
  module Domain
    class Freshness
      Policy = Data.define(:ttl_seconds, :on_stale, :sync_budget_ms) do
        def decide(verdict)
          return Action::Return.new if verdict.fresh?

          case on_stale
          when :warn       then Action::Return.new
          when :sync       then Action::FetchSync.new
          when :timed_sync then Action::FetchTimed.new(budget_ms: sync_budget_ms)
          else                  Action::Return.new
          end
        end
      end
    end
  end
end
