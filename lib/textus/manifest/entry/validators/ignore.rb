module Textus
  class Manifest
    class Entry
      module Validators
        # Validates the per-entry `ignore:` field (ADR 0042): a list of
        # non-empty glob strings, allowed only on nested entries.
        module Ignore
          def self.call(entry, policy: nil) # rubocop:disable Lint/UnusedMethodArgument
            patterns = entry.raw["ignore"]
            return if patterns.nil?

            raise UsageError.new("entry '#{entry.key}': ignore requires nested: true") unless entry.nested?

            raise UsageError.new("entry '#{entry.key}': ignore must be a list of glob strings") unless patterns.is_a?(Array)

            patterns.each do |pat|
              next if pat.is_a?(String) && !pat.empty?

              raise UsageError.new(
                "entry '#{entry.key}': each ignore pattern must be a non-empty string (got #{pat.inspect})",
              )
            end
          end
        end
      end
    end
  end
end
