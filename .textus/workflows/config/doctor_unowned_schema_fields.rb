# Replaces Doctor::Check::UnownedSchemaFields. Reports schema fields that do
# not declare maintained_by.

# rubocop:disable Metrics/BlockLength
Textus.workflow "doctor-unowned-schema-fields" do
  match "artifacts.doctor.unowned-schema-fields"

  step :scan do |_, ctx|
    dir = ctx.layout.schemas_dir
    issues = []

    if File.directory?(dir)
      Dir.glob(File.join(dir, "*.yaml")).each do |path|
        schema = begin
          Textus::Schema.load(path)
        rescue StandardError
          nil
        end
        next if schema.nil?

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
# rubocop:enable Metrics/BlockLength
