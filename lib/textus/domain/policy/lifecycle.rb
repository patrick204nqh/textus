module Textus
  module Domain
    module Policy
      # Unified per-entry lifecycle policy (ADR 0079): one ttl + one action.
      # Replaces the separate Fetch (ttl/on_stale) and Retention
      # (expire_after/archive_after) policies. The action's destructiveness
      # decides WHERE it runs: lazy actions (refresh/warn) on get/list reads;
      # destructive actions (drop/archive) only on the reconcile sweep.
      class Lifecycle
        LAZY        = %i[refresh warn].freeze
        DESTRUCTIVE = %i[drop archive].freeze
        ALLOWED     = (LAZY + DESTRUCTIVE).freeze

        attr_reader :on_expire, :budget_ms

        def initialize(ttl:, on_expire:, budget_ms: nil, allowed: ALLOWED)
          action = on_expire.is_a?(Symbol) ? on_expire : on_expire.to_s.to_sym
          unless allowed.include?(action)
            raise Textus::UsageError.new(
              "lifecycle action must be one of #{allowed.join("|")}, got #{on_expire.inspect}",
            )
          end

          @ttl       = ttl
          @on_expire = action
          @budget_ms = budget_ms
        end

        def ttl_seconds = Textus::Domain::Duration.seconds(@ttl)
        def destructive? = DESTRUCTIVE.include?(@on_expire)
        def lazy?        = LAZY.include?(@on_expire)
      end
    end
  end
end
