# Replaces Doctor::Check::ManifestFiles + Doctor::Check::Templates + Doctor::Check::Schemas.
# Checks every declared entry has a file on disk, all publish templates exist,
# and all declared schemas exist.

Textus.workflow "manifest-files" do
  match "artifacts.doctor.manifest-files"

  step :check do |_, ctx|
    manifest = ctx.manifest
    file_system = ctx.file_system
    layout = ctx.layout
    schemas = ctx.schemas
    issues = []

    manifest.data.entries.each do |entry|
      next if entry.nested? || entry.derived? || entry.external?

      path = Textus::Protocol::Key::Path.resolve(manifest.data, entry)
      unless file_system.exists?(path)
        issues << { "code" => "manifest.missing_file", "severity" => "info",
                    "subject" => entry.key,
                    "message" => "declared entry has no file on disk at #{path}",
                    "fix" => "create the entry with 'textus put #{entry.key} --stdin --as=<role>'" }
      end

      entry.publish_to.each do |target|
        tmpl = target.respond_to?(:template) ? target.template : nil
        next unless tmpl

        to_path = target.respond_to?(:to) ? target.to : target.to_s
        tpath = layout.template_path(tmpl)
        next if File.exist?(tpath)

        issues << { "code" => "publish.missing_template", "severity" => "warning",
                    "subject" => entry.key,
                    "message" => "publish target '#{to_path}' references missing template '#{tmpl}'",
                    "fix" => "create the template at #{tpath}" }
      end

      next unless entry.schema
      next if schemas.fetch_or_nil(entry.schema)

      issues << { "code" => "manifest.missing_schema", "severity" => "warning",
                  "subject" => entry.key,
                  "message" => "entry '#{entry.key}' declares schema '#{entry.schema}' but no schema file found",
                  "fix" => "add the schema file to schemas/ directory" }
    end

    { "content" => { "ok" => issues.empty?, "issues" => issues, "count" => issues.size } }
  end

  publish
end
