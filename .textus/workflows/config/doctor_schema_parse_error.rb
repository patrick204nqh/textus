# Replaces Doctor::Check::SchemaParseError. Checks schema YAML parseability.

Textus.workflow "doctor-schema-parse-error" do
  match "artifacts.doctor.schema-parse-error"

  step :scan do |_, ctx|
    dir = ctx.container.layout.schemas_dir
    issues = []

    if File.directory?(dir)
      Dir.glob(File.join(dir, "*.yaml")).each do |path|
        begin
          Textus::Schema.load(path)
        rescue StandardError => e
          issues << {
            "code" => "schema.parse_error",
            "level" => "error",
            "subject" => path,
            "message" => "schema failed to parse: #{e.class}: #{e.message}",
            "fix" => "fix the YAML at #{path} (check indentation, quoted scalars, and aliases)",
          }
        end
      end
    end

    { "content" => { "ok" => issues.empty?, "issues" => issues, "count" => issues.size } }
  end

  publish
end
