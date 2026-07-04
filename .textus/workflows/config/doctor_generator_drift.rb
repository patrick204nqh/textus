Textus.workflow "doctor-generator-drift" do
  match "artifacts.doctor.generator-drift"

  step :scan do |_, ctx|
    issues = []
    root = ctx.layout.root

    ctx.manifest.data.entries.each do |entry|
      next unless entry.derived? || entry.external?
      next unless entry.sources && !entry.sources.empty?

      entry_path = entry.path ? File.join(root, entry.path) : nil
      next unless entry_path && File.exist?(entry_path)

      entry_mtime = File.mtime(entry_path)

      entry.sources.each do |src|
        src_path = File.join(root, src)
        next unless File.exist?(src_path)

        if File.mtime(src_path) > entry_mtime
          issues << {
            "code" => "generator_drift",
            "level" => "warning",
            "subject" => entry.key,
            "message" => "source '#{src}' is newer than produced entry '#{entry.key}'",
            "fix" => "rematerialize the entry: `textus drain`",
          }
        end
      end
    end

    { "content" => { "ok" => issues.empty?, "issues" => issues, "count" => issues.size } }
  end

  publish
end
