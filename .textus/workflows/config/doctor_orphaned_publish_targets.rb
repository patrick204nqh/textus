# Replaces Doctor::Check::OrphanedPublishTargets. Flags published files whose
# recorded store source no longer exists.

Textus.workflow "doctor-orphaned-publish-targets" do
  match "artifacts.doctor.orphaned-publish-targets"

  step :scan do |_, ctx|
    sdir = ctx.layout.sentinels_root
    issues = []

    if File.directory?(sdir)
      repo_root = File.dirname(ctx.layout.root)
      store = Textus::Port::SentinelStore.new
      glob = File.join(sdir, "**", "*#{Textus::Port::SentinelStore::SUFFIX}")

      Dir.glob(glob).each do |spath|
        sentinel = store.load(spath, repo_root)
        next if sentinel.nil? || sentinel.source.nil?
        next if File.exist?(sentinel.source)

        issues << {
          "code" => "publish.orphaned_target",
          "level" => "warning",
          "subject" => sentinel.target,
          "message" => "published file #{sentinel.target} has no source in the store " \
                       "(recorded source #{sentinel.source} is gone) — likely a renamed or removed leaf",
          "fix" => "remove the stale copy and its sentinel: rm '#{sentinel.target}' '#{spath}'",
        }
      end
    end

    { "content" => { "ok" => issues.empty?, "issues" => issues, "count" => issues.size } }
  end

  publish
end
