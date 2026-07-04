Textus.workflow "naming-check" do
  match "artifacts.doctor.naming-check"

  step :scan do |_, ctx|
    manifest = ctx.manifest
    issues = []

    manifest.data.entries.each do |entry|
      next unless entry.naming

      pattern = Textus::Protocol::V4::NAMING_PATTERNS.fetch(entry.naming)
      root = ctx.layout.root
      base = File.join(root, Textus::Protocol::Key::Path.normalize_relative_path(entry.path))
      next unless File.directory?(base)

      ext_glob = entry.format == "md" ? "*.md" : "*"
      Dir.glob(File.join(base, "**", ext_glob)).each do |path|
        filename = File.basename(path)
        next if pattern.match?(filename)

        rel = path.sub(%r{\A#{Regexp.escape(base)}/?}, "")
        stem = rel.sub(/#{Regexp.escape(File.extname(rel))}\z/, "")
        segs = stem.split("/").reject(&:empty?)
        key = ([entry.key] + segs).join(".")

        issues << {
          "code" => "loop.naming",
          "level" => "warning",
          "subject" => key,
          "message" => "#{filename} does not match the required naming pattern for #{entry.key} (#{entry.naming})",
          "fix" => "rename to match #{pattern.inspect}",
        }
      end
    end

    { "content" => { "ok" => issues.empty?, "issues" => issues, "count" => issues.size } }
  end

  publish
end
