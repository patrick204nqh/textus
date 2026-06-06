module Textus
  module Key
    # Dotted-key scope matching, shared by all prefix-scoped sweeps
    # (WS4 / ADR 0089-era cleanup). Canonicalised here so every consumer
    # uses a consistent dotted-boundary check with proper Nested ancestor
    # handling. ADR 0093: Produce is the sole engine calling this.
    module Matching
      module_function

      # Is `key` within the `prefix` scope?
      #   - exact match, or a dotted descendant (the `prefix.` boundary, so
      #     prefix "art" does NOT match key "artifacts"), and
      #   - for a nested entry, also when `prefix` descends INTO it — the nested
      #     parent owns the leaf the prefix names (e.g. prefix
      #     "feeds.machines.host1" still selects the nested entry
      #     "feeds.machines").
      def matches_prefix?(key, prefix, nested: false)
        return true if key == prefix || key.start_with?("#{prefix}.")

        nested && prefix.start_with?("#{key}.")
      end
    end
  end
end
