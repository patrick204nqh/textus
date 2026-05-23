module Textus
  module Doctor
    class Check
      class UnownedSchemaFields < Check
        def call
          dir = File.join(store.root, "schemas")
          return [] unless File.directory?(dir)

          Dir.glob(File.join(dir, "*.yaml")).flat_map do |path|
            issues_for(path)
          end
        end

        private

        def issues_for(path)
          schema = safe_load(path)
          return [] if schema.nil?

          unowned = schema.unowned_fields
          return [] if unowned.empty?

          [{
            "code" => "schema.unowned_fields",
            "level" => "info",
            "subject" => schema.name || File.basename(path, ".yaml"),
            "message" => "schema has fields without maintained_by: #{unowned.join(", ")}",
            "fix" => "add 'maintained_by: <role>' to each field in #{path} (optional but recommended)",
          }]
        end

        def safe_load(path)
          Schema.load(path)
        rescue StandardError
          nil
        end
      end
    end
  end
end
