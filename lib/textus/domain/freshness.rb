# frozen_string_literal: true

module Textus
  module Domain
    # Value object describing the freshness annotation attached to an Envelope
    # after a freshness evaluation. Replaces the loose Hash that used to live
    # on `Envelope#freshness`.
    #
    # Note on wire format: `#to_h_for_wire` is intentionally narrower than the
    # full field set. It emits the legacy keys ("stale", "stale_reason",
    # "fetching", and "fetch_error" when present) so the CLI JSON wire
    # stays byte-identical with textus/3. The gem-side fields `checked_at`
    # and `ttl_remaining_ms` are NOT emitted on the wire in this phase.
    Freshness = Data.define(
      :stale, :fetching, :reason, :fetch_error, :checked_at, :ttl_remaining_ms
    ) do
      def self.build(stale:, fetching: false, reason: nil, fetch_error: nil,
                     checked_at: nil, ttl_remaining_ms: nil)
        new(
          stale: stale,
          fetching: fetching,
          reason: reason,
          fetch_error: fetch_error,
          checked_at: checked_at,
          ttl_remaining_ms: ttl_remaining_ms,
        )
      end

      def to_h_for_wire
        h = {
          "stale" => stale,
          "stale_reason" => reason,
          "fetching" => fetching,
        }
        h["fetch_error"] = fetch_error unless fetch_error.nil?
        h
      end
    end
  end
end
