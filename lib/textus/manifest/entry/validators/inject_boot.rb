module Textus
  class Manifest
    class Entry
      module Validators
        module InjectBoot
          def self.call(entry)
            inject_boot = entry.respond_to?(:inject_boot) ? entry.inject_boot : false
            return unless inject_boot

            raise UsageError.new("entry '#{entry.key}': inject_boot: is only valid on derived entries") unless entry.in_generator_zone?

            has_template = entry.respond_to?(:template) && !entry.template.nil?
            return if has_template

            raise UsageError.new("entry '#{entry.key}': inject_boot: requires a template:")
          end
        end
      end
    end
  end
end
