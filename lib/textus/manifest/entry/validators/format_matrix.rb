module Textus
  class Manifest
    class Entry
      module Validators
        module FormatMatrix
          def self.call(entry, policy:) # rubocop:disable Lint/UnusedMethodArgument
            begin
              Textus::Entry.for_format(entry.format).validate_path_extension(entry.path, entry.nested?)
            rescue UsageError => e
              raise UsageError.new("entry '#{entry.key}': #{e.message}")
            end

            if entry.format == "text" && !entry.schema.nil?
              raise UsageError.new("entry '#{entry.key}': text format must not declare a schema")
            end

            has_template = !entry.template.nil?
            return unless entry.derived? && entry.projection? && !has_template &&
                          %w[markdown text].include?(entry.format) && !entry.nested?

            raise UsageError.new("entry '#{entry.key}': #{entry.format} entries in a generator zone require a template")
          end
        end
      end
    end
  end
end
