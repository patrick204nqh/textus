module Textus
  class Manifest
    class Entry
      module Validators
        module InjectBoot
          def self.call(entry, policy:) # rubocop:disable Lint/UnusedMethodArgument
            return unless entry.inject_boot

            raise UsageError.new("entry '#{entry.key}': inject_boot: is only valid on derived entries") unless entry.derived?

            return unless entry.template.nil?

            raise UsageError.new("entry '#{entry.key}': inject_boot: requires a template:")
          end
        end
      end
    end
  end
end
