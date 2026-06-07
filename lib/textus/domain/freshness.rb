# frozen_string_literal: true

module Textus
  module Domain
    # Currency — "is the stored data stale relative to its source?" (ADR 0099).
    # The home of the single Freshness evaluator and its Verdict value object.
    # Distinct from Domain::Retention (GC dueness, Q2).
    module Freshness
    end
  end
end
