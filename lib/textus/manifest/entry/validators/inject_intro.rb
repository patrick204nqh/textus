module Textus
  class Manifest
    class Entry
      module Validators
        module InjectIntro
          def self.call(entry)
            inject_intro = entry.respond_to?(:inject_intro) ? entry.inject_intro : false
            return unless inject_intro

            raise UsageError.new("entry '#{entry.key}': inject_intro: is only valid on derived entries") unless entry.in_generator_zone?

            has_template = entry.respond_to?(:template) && !entry.template.nil?
            return if has_template

            raise UsageError.new("entry '#{entry.key}': inject_intro: requires a template:")
          end
        end
      end
    end
  end
end
