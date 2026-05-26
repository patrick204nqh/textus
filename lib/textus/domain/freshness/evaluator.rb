require "time"

module Textus
  module Domain
    module Freshness
      module Evaluator
        module_function

        def call(policy, envelope, now:)
          return Verdict.fresh if policy.ttl_seconds.nil?

          last_str = envelope&.meta&.dig("last_refreshed_at")
          return Verdict.stale("never refreshed") if last_str.nil?

          last = begin
            Time.parse(last_str.to_s)
          rescue ArgumentError, TypeError
            nil
          end
          return Verdict.stale("unparseable last_refreshed_at: #{last_str.inspect}") if last.nil?

          age = now - last
          return Verdict.fresh if age <= policy.ttl_seconds

          Verdict.stale("ttl exceeded (age=#{age.to_i}s, ttl=#{policy.ttl_seconds}s)")
        end
      end
    end
  end
end
