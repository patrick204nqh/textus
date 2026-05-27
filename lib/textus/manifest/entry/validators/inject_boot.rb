module Textus
  class Manifest
    class Entry
      module Validators
        module InjectBoot
          def self.call(entry)
            return unless entry.inject_boot

            raise UsageError.new("entry '#{entry.key}': inject_boot: is only valid on derived entries") unless entry.in_generator_zone?

            return unless entry.template.nil?

            raise UsageError.new("entry '#{entry.key}': inject_boot: requires a template:")
          end
        end
      end
    end
  end
end
