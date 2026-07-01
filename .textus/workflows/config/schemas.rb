# Replaces Doctor::Check::Schemas. Checks every declared schema file exists.

Textus.workflow "schemas" do
  match "artifacts.doctor.schemas"

  step :check do |_, ctx|
    manifest = ctx.container.manifest
    schemas = ctx.container.schemas
    issues = []
    manifest.data.entries.each do |entry|
      next unless entry.schema
      next if schemas.fetch_or_nil(entry.schema)
      issues << { "code" => "manifest.missing_schema", "severity" => "warning",
                  "subject" => entry.key,
                  "message" => "entry '#{entry.key}' declares schema '#{entry.schema}' but no schema file found",
                  "fix" => "create the schema: 'textus schema init #{entry.schema} --from=#{entry.key}'" }
    end
    { "content" => { "ok" => issues.empty?, "issues" => issues, "count" => issues.size } }
  end

  publish
end
