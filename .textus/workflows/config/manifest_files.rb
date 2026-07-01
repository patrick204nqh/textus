# Replaces Doctor::Check::ManifestFiles. Checks every declared entry has a file on disk.

Textus.workflow "manifest-files" do
  match "artifacts.doctor.manifest-files"

  step :check do |_, ctx|
    manifest = ctx.container.manifest
    file_store = ctx.container.file_store
    issues = []
    manifest.data.entries.each do |entry|
      next if entry.nested? || entry.derived? || entry.external?
      path = Textus::Key::Path.resolve(manifest.data, entry)
      next if file_store.exists?(path)
      issues << { "code" => "manifest.missing_file", "severity" => "info",
                  "subject" => entry.key,
                  "message" => "declared entry has no file on disk at #{path}",
                  "fix" => "create the entry with 'textus put #{entry.key} --stdin --as=<role>'" }
    end
    { "content" => { "ok" => issues.empty?, "issues" => issues, "count" => issues.size } }
  end

  publish
end
