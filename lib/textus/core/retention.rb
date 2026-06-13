# frozen_string_literal: true

module Textus
  module Core
    # Retention — "is the entry old enough to retire?" (Q2, ADR 0093/0099).
    # GC dueness, orthogonal to Freshness (content currency). The reporter is
    # Core::Retention::Sweep; the manifest rule policy is Manifest::Policy::Retention.
    module Retention
    end
  end
end
