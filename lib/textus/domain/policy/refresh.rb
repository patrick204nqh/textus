module Textus
  module Domain
    module Policy
      class Refresh
        ALLOWED_ON_STALE = %i[warn sync timed_sync].freeze

        attr_reader :ttl, :on_stale, :sync_budget_ms, :fetch_timeout_seconds

        def initialize(ttl:, on_stale:, sync_budget_ms:, fetch_timeout_seconds: nil)
          on_stale_sym = on_stale.is_a?(Symbol) ? on_stale : on_stale.to_s.to_sym
          unless ALLOWED_ON_STALE.include?(on_stale_sym)
            raise Textus::UsageError.new(
              "on_stale must be one of #{ALLOWED_ON_STALE.join(", ")} (got #{on_stale.inspect})",
            )
          end

          @ttl                   = ttl
          @on_stale              = on_stale_sym
          @sync_budget_ms        = sync_budget_ms
          @fetch_timeout_seconds = fetch_timeout_seconds
        end

        def ttl_seconds
          return nil if @ttl.nil?

          str = @ttl.to_s.strip
          return str.to_i if str.match?(/\A\d+\z/)

          m = str.match(/\A(\d+)\s*([smhd])\z/)
          return nil unless m

          n = m[1].to_i
          case m[2]
          when "s" then n
          when "m" then n * 60
          when "h" then n * 3600
          when "d" then n * 86_400
          end
        end

        def to_freshness_policy
          Textus::Domain::Freshness::Policy.new(
            ttl_seconds: ttl_seconds,
            on_stale: @on_stale,
            sync_budget_ms: @sync_budget_ms,
          )
        end
      end
    end
  end
end
