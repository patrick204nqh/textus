module Textus
  module Doctor
    class Check
      class Sentinels < Check
        def call
          store      = Textus::Port::SentinelStore.new
          file_stat  = Textus::Port::Storage::FileStat.new
          dir        = Textus::Store::Layout.new(root).sentinels_root
          return [] unless file_stat.directory?(dir)

          repo_root = File.dirname(root)
          file_stat.glob(File.join(dir, "**", "*#{Textus::Port::SentinelStore::SUFFIX}")).flat_map do |sentinel_path|
            inspect_sentinel(sentinel_path, repo_root, store, file_stat)
          end
        end

        private

        def inspect_sentinel(sentinel_path, repo_root, store, file_stat)
          sentinel = store.load(sentinel_path, repo_root)
          return [parse_error_issue(sentinel_path)] if sentinel.nil?
          return [orphan_issue(sentinel_path, sentinel)] if sentinel.orphan?(file_stat)
          return [drift_issue(sentinel)] if sentinel.drift?(file_stat)

          []
        end

        def parse_error_issue(sentinel_path)
          {
            "code" => "sentinel.parse_error",
            "level" => "warning",
            "subject" => sentinel_path,
            "message" => "sentinel is not valid JSON",
            "fix" => "delete #{sentinel_path} and re-run 'textus drain' to regenerate",
          }
        end

        def orphan_issue(sentinel_path, sentinel)
          {
            "code" => "sentinel.orphan",
            "level" => "warning",
            "subject" => sentinel_path,
            "message" => "sentinel target #{sentinel.target.inspect} no longer exists",
            "fix" => "delete #{sentinel_path} (the published file is gone) or restore the target",
          }
        end

        def drift_issue(sentinel)
          {
            "code" => "sentinel.drift",
            "level" => "warning",
            "subject" => sentinel.target,
            "message" => "published file at #{sentinel.target} was modified out-of-band",
            "fix" => "re-run 'textus drain' to overwrite, or copy the manual edit back into the store source",
          }
        end
      end
    end
  end
end
