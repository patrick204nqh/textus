module Textus
  class Manifest
    class Entry
      module Validators
        module InjectBoot
          def self.call(entry, policy:)
            return unless entry.inject_boot

            unless entry.in_generator_zone?(policy)
              raise UsageError.new("entry '#{entry.key}': inject_boot: is only valid on derived entries")
            end

            return unless entry.template.nil?

            raise UsageError.new("entry '#{entry.key}': inject_boot: requires a template:")
          end
        end
      end
    end
  end
end
