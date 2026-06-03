module Textus
  module Doctor
    class Check
      # Flags published files whose recorded source no longer exists in the
      # store. Per-leaf prune (ADR 0046) reconciles within a still-present
      # leaf; a renamed or removed *whole* leaf orphans its entire target
      # directory, which a per-entry build won't revisit. This check catches
      # that drift without making `build` scan globally.
      class OrphanedPublishTargets < Check
        def call
          sdir = File.join(root, Textus::Ports::SentinelStore::DIR)
          return [] unless File.directory?(sdir)

          repo_root = File.dirname(root)
          store = Textus::Ports::SentinelStore.new
          glob = File.join(sdir, "**", "*#{Textus::Ports::SentinelStore::SUFFIX}")
          Dir.glob(glob).filter_map do |spath|
            sentinel = store.load(spath, repo_root)
            next nil if sentinel.nil? || sentinel.source.nil?
            next nil if File.exist?(sentinel.source)

            {
              "code" => "publish.orphaned_target",
              "level" => "warning",
              "subject" => sentinel.target,
              "message" => "published file #{sentinel.target} has no source in the store " \
                           "(recorded source #{sentinel.source} is gone) — likely a renamed or removed leaf",
              "fix" => "remove the stale copy and its sentinel: rm '#{sentinel.target}' '#{spath}'",
            }
          end
        end
      end
    end
  end
end
