# frozen_string_literal: true

module Textus
  module Domain
    module Policy
      # The CLOSED floor (ADR 0031 §4): predicate names every transition
      # evaluates regardless of rules:. rules[].guard only ADDS to these.
      module BaseGuards
        # The minimal floor — only what the verb is meaningless without.
        # schema_valid / etag_match / fresh_within are NOT here: they are
        # composable-only, added per-key via rules[].guard (ADR 0031).
        BASE = {
          put: %w[zone_writable_by],
          key_delete: %w[zone_writable_by],
          key_mv: %w[zone_writable_by],
          accept: %w[author_held target_is_canon],
          reject: %w[author_held],
          reconcile: %w[zone_writable_by],
        }.freeze

        def self.for(transition) = BASE.fetch(transition, [])
      end
    end
  end
end
