# frozen_string_literal: true

module Textus
  class Store
    module Freshness
      # Thin facade delegating to the focused TtlEvaluator and DriftDetector.
      # Prefer using TtlEvaluator or DriftDetector directly.
      class Evaluator
        def initialize(manifest:, file_stat:, clock:)
          @ttl   = TtlEvaluator.new(manifest: manifest, file_stat: file_stat, clock: clock)
          @drift = DriftDetector.new(manifest: manifest, file_stat: file_stat, clock: clock)
        end

        def verdict(mentry) = @ttl.verdict(mentry)
        def stale_keys(**) = @ttl.stale_keys(**)
        def drift_rows(mentry) = @drift.drift_rows(mentry)
      end
    end
  end
end
