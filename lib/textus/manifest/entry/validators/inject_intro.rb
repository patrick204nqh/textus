module Textus
  class Manifest
    class Entry
      module Validators
        module InjectIntro
          def self.call(entry)
            return unless entry.inject_intro

            raise UsageError.new("entry '#{entry.key}': inject_intro: is only valid on derived entries") unless entry.in_generator_zone?
            return unless entry.template.nil?

            raise UsageError.new("entry '#{entry.key}': inject_intro: requires a template:")
          end
        end
      end
    end
  end
end
