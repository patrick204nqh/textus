module Textus
  class Store
    class Staleness
      module EntryFilter
        module_function

        # Returns true when this entry should be considered by a staleness check.
        # Mirrors the inline `next if zone && ...; next if prefix && ...` checks
        # that previously appeared in both loops.
        def match?(mentry, prefix:, zone:)
          return false if zone && mentry.zone != zone
          return false if prefix && !(mentry.key == prefix || mentry.key.start_with?("#{prefix}."))

          true
        end
      end
    end
  end
end
