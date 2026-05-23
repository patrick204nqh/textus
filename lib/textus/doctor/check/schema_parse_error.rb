module Textus
  module Doctor
    class Check
      # Surfaces YAML parse failures for files in <store>/schemas/. Without
      # this check, malformed schemas are silently skipped by other doctor
      # checks (UnownedSchemaFields rescues, Schemas only checks filenames),
      # leaving the operator with no signal that a schema is broken.
      class SchemaParseError < Check
        def call
          dir = File.join(store.root, "schemas")
          return [] unless File.directory?(dir)

          Dir.glob(File.join(dir, "*.yaml")).each_with_object([]) do |path, out|
            Schema.load(path)
          rescue StandardError => e
            out << {
              "code" => "schema.parse_error",
              "level" => "error",
              "subject" => path,
              "message" => "schema failed to parse: #{e.class}: #{e.message}",
              "fix" => "fix the YAML at #{path} (check indentation, quoted scalars, and aliases)",
            }
          end
        end
      end
    end
  end
end
