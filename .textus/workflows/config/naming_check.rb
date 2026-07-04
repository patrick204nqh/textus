Textus.workflow "naming-check" do
  match "artifacts.doctor.naming-check"

  step :scan do |_, ctx|
    manifest = ctx.manifest
    issues = []

    manifest.data.entries.each do |entry|
      next unless entry.naming

      pattern = Textus::Protocol::V4::NAMING_PATTERNS.fetch(entry.naming)

      ctx.manifest.resolver.enumerate(prefix: entry.key).each do |row|
        filename = File.basename(row[:path])
        next if pattern.match?(filename)

        issues << {
          "code" => "loop.naming",
          "level" => "warning",
          "subject" => row[:key],
          "message" => "#{filename} does not match the required naming pattern for #{entry.key} (#{entry.naming})",
          "fix" => "rename to match #{pattern.inspect}",
        }
      end
    end

    { "content" => { "ok" => issues.empty?, "issues" => issues, "count" => issues.size } }
  end

  publish
end
