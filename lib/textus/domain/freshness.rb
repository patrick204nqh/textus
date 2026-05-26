# frozen_string_literal: true

module Textus
  module Domain
    # Value object describing the freshness annotation attached to an Envelope
    # after a freshness evaluation. Replaces the loose Hash that used to live
    # on `Envelope#freshness`.
    #
    # Note on wire format: `#to_h_for_wire` is intentionally narrower than the
    # full field set. It emits the legacy keys ("stale", "stale_reason",
    # "refreshing", and "refresh_error" when present) so the CLI JSON wire
    # stays byte-identical with textus/3. The gem-side fields `checked_at`
    # and `ttl_remaining_ms` are NOT emitted on the wire in this phase.
    Freshness = Data.define(
      :stale, :refreshing, :reason, :refresh_error, :checked_at, :ttl_remaining_ms
    ) do
      def self.build(stale:, refreshing: false, reason: nil, refresh_error: nil,
                     checked_at: nil, ttl_remaining_ms: nil)
        new(
          stale: stale,
          refreshing: refreshing,
          reason: reason,
          refresh_error: refresh_error,
          checked_at: checked_at,
          ttl_remaining_ms: ttl_remaining_ms,
        )
      end

      def to_h_for_wire
        h = {
          "stale" => stale,
          "stale_reason" => reason,
          "refreshing" => refreshing,
        }
        h["refresh_error"] = refresh_error unless refresh_error.nil?
        h
      end
    end
  end
end
