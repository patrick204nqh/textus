Textus.workflow "naming-check" do
  match "artifacts.doctor.naming-check"

  step :scan do |_, ctx|
    manifest = ctx.container.manifest
    issues = []

    manifest.data.entries.each do |entry|
      next unless entry.naming

      pattern = Textus::Protocol::V4::NAMING_PATTERNS.fetch(entry.naming)
      root = ctx.container.root
      resolved = File.join(root, Textus::Key::Path.normalize_relative_path(entry.path))
      next unless File.directory?(resolved)

      Dir.children(resolved).each do |filename|
        next if pattern.match?(filename)

        issues << {
          "code" => "loop.naming",
          "level" => "warning",
          "subject" => "#{entry.key}.#{filename}",
          "message" => "#{filename} does not match the required naming pattern for #{entry.key} (#{entry.naming})",
          "fix" => "rename to match #{pattern.inspect}",
        }
      end
    end

    { "content" => { "ok" => issues.empty?, "issues" => issues, "count" => issues.size } }
  end

  publish
end
