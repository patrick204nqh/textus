# Replaces Doctor::Check::SchemaParseError + Doctor::Check::UnownedSchemaFields.
# Checks schema YAML parseability and field ownership metadata.

Textus.workflow "doctor-schema-parse-error" do
  match "artifacts.doctor.schema-parse-error"

  step :scan do |_, ctx|
    dir = ctx.layout.schemas_dir
    issues = []

    if File.directory?(dir)
      Dir.glob(File.join(dir, "*.yaml")).each do |path|
        schema = begin
          Textus::Schema.load(path)
        rescue StandardError => e
          issues << {
            "code" => "schema.parse_error",
            "level" => "error",
            "subject" => path,
            "message" => "schema failed to parse: #{e.class}: #{e.message}",
            "fix" => "fix the YAML at #{path} (check indentation, quoted scalars, and aliases)",
          }
          next
        end

        unowned = schema.unowned_fields
        next if unowned.empty?

        issues << {
          "code" => "schema.unowned_fields",
          "level" => "info",
          "subject" => schema.name || File.basename(path, ".yaml"),
          "message" => "schema has fields without maintained_by: #{unowned.join(", ")}",
          "fix" => "add 'maintained_by: <role>' to each field in #{path} (optional but recommended)",
        }
      end
    end

    { "content" => { "ok" => issues.empty?, "issues" => issues, "count" => issues.size } }
  end

  publish
end
