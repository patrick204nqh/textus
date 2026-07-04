Textus.workflow "doctor-sentinels" do
  match "artifacts.doctor.sentinels"

  step :scan do |_, ctx|
    dir = ctx.layout.sentinels_root
    issues = []

    if File.directory?(dir)
      Dir.glob(File.join(dir, "**", "*.sentinel.json")).each do |sentinel_path|
        sentinel = begin
          JSON.parse(File.read(sentinel_path))
        rescue
          nil
        end
        if sentinel.nil?
          issues << { "code" => "sentinel.parse_error", "level" => "warning", "subject" => sentinel_path,
                      "message" => "sentinel is not valid JSON",
                      "fix" => "delete and re-run 'textus drain' to regenerate" }
          next
        end

        target = sentinel["target"]
        if target && !File.exist?(target)
          issues << { "code" => "sentinel.orphan", "level" => "warning", "subject" => target,
                      "message" => "sentinel target #{target} no longer exists",
                      "fix" => "delete #{sentinel_path} or restore the target" }
        end
      end
    end

    { "content" => { "ok" => issues.empty?, "issues" => issues, "count" => issues.size } }
  end

  publish
end
