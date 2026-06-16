module Textus
  class Manifest
    class Entry
      module Validators
        module FormatMatrix
          def self.call(entry, policy:) # rubocop:disable Lint/UnusedMethodArgument
            begin
              Textus::Format.for(entry.format).validate_path_extension(entry.path, entry.nested?)
            rescue UsageError => e
              raise UsageError.new("entry '#{entry.key}': #{e.message}")
            end

            return unless entry.format == "text" && !entry.schema.nil?

            raise UsageError.new("entry '#{entry.key}': text format must not declare a schema")
          end
        end
      end
    end
  end
end
