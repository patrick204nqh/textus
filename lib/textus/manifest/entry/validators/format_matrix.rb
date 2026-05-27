module Textus
  class Manifest
    class Entry
      module Validators
        module FormatMatrix
          def self.call(entry)
            begin
              Textus::Entry.for_format(entry.format).validate_path_extension(entry.path, entry.nested?)
            rescue UsageError => e
              raise UsageError.new("entry '#{entry.key}': #{e.message}")
            end

            if entry.format == "text" && !entry.schema.nil?
              raise UsageError.new("entry '#{entry.key}': text format must not declare a schema")
            end

            has_template = entry.respond_to?(:template) && !entry.template.nil?
            is_external   = entry.derived? && entry.external?
            return unless entry.in_generator_zone? && !has_template && !is_external &&
                          %w[markdown text].include?(entry.format) && !entry.nested?

            raise UsageError.new("entry '#{entry.key}': derived #{entry.format} entries require a template")
          end
        end
      end
    end
  end
end
