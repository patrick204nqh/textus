module Textus
  module Key
    # Dotted-key scope matching, shared by the two prefix-scoped sweeps
    # (WS4 / ADR 0089-era cleanup): Maintenance::Materialize and
    # Domain::Lifecycle both ask "does this entry fall within a prefix?" and
    # had drifted — materialize used a loose `start_with?(prefix)` plus a
    # Nested ancestor case; lifecycle used a dotted boundary but omitted the
    # Nested case. This is the one definition both now call.
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
