# frozen_string_literal: true

module Textus
  module Core
    # Currency — "is the stored data stale relative to its source?" (ADR 0099).
    # The home of the single Freshness evaluator and its Verdict value object.
    # Distinct from Core::Retention (GC dueness, Q2).
    module Freshness
    end
  end
end
