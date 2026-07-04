# Replaces Doctor::Check::Sentinels. Checks sentinel JSON integrity and
# published-file drift/orphans.

# rubocop:disable Metrics/BlockLength
Textus.workflow "doctor-sentinels" do
  match "artifacts.doctor.sentinels"

  step :scan do |_, ctx|
    store = Textus::Port::SentinelStore.new
    file_stat = Textus::Port::Storage::FileStat.new
    dir = ctx.layout.sentinels_root
    issues = []

    if file_stat.directory?(dir)
      repo_root = File.dirname(ctx.layout.root)
      pattern = File.join(dir, "**", "*#{Textus::Port::SentinelStore::SUFFIX}")

      file_stat.glob(pattern).each do |sentinel_path|
        sentinel = store.load(sentinel_path, repo_root)
        if sentinel.nil?
          issues << {
            "code" => "sentinel.parse_error",
            "level" => "warning",
            "subject" => sentinel_path,
            "message" => "sentinel is not valid JSON",
            "fix" => "delete #{sentinel_path} and re-run 'textus drain' to regenerate",
          }
          next
        end

        if sentinel.orphan?(file_stat)
          issues << {
            "code" => "sentinel.orphan",
            "level" => "warning",
            "subject" => sentinel_path,
            "message" => "sentinel target #{sentinel.target.inspect} no longer exists",
            "fix" => "delete #{sentinel_path} (the published file is gone) or restore the target",
          }
          next
        end

        next unless sentinel.drift?(file_stat)

        issues << {
          "code" => "sentinel.drift",
          "level" => "warning",
          "subject" => sentinel.target,
          "message" => "published file at #{sentinel.target} was modified out-of-band",
          "fix" => "re-run 'textus drain' to overwrite, or copy the manual edit back into the store source",
        }
      end
    end

    { "content" => { "ok" => issues.empty?, "issues" => issues, "count" => issues.size } }
  end

  publish
end
# rubocop:enable Metrics/BlockLength
