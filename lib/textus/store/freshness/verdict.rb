module Textus
  class Store
    module Freshness
      Verdict = Data.define(
        :stale, :fetching, :reason, :fetch_error, :checked_at, :ttl_remaining_ms
      ) do
        def self.build(stale:, fetching: false, reason: nil, fetch_error: nil,
                       checked_at: nil, ttl_remaining_ms: nil)
          new(
            stale: stale, fetching: fetching, reason: reason,
            fetch_error: fetch_error, checked_at: checked_at,
            ttl_remaining_ms: ttl_remaining_ms
          )
        end

        def to_h_for_wire
          h = { "stale" => stale, "stale_reason" => reason, "fetching" => fetching }
          h["fetch_error"] = fetch_error unless fetch_error.nil?
          h
        end
      end
    end
  end
end
