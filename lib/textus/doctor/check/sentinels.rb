module Textus
  module Doctor
    class Check
      class Sentinels < Check
        def call
          dir = File.join(root, "sentinels")
          return [] unless File.directory?(dir)

          repo_root = File.dirname(root)
          Dir.glob(File.join(dir, "**", "*#{Textus::Domain::Sentinel::SUFFIX}")).flat_map do |sentinel_path|
            inspect_sentinel(sentinel_path, repo_root)
          end
        end

        private

        def inspect_sentinel(sentinel_path, repo_root)
          sentinel = Textus::Domain::Sentinel.load(sentinel_path, repo_root)
          return [parse_error_issue(sentinel_path)] if sentinel.nil?
          return [orphan_issue(sentinel_path, sentinel)] if sentinel.orphan?
          return [drift_issue(sentinel)] if sentinel.drift?

          []
        end

        def parse_error_issue(sentinel_path)
          {
            "code" => "sentinel.parse_error",
            "level" => "warning",
            "subject" => sentinel_path,
            "message" => "sentinel is not valid JSON",
            "fix" => "delete #{sentinel_path} and re-run 'textus build' to regenerate",
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
            "fix" => "re-run 'textus build' to overwrite, or copy the manual edit back into the store source",
          }
        end
      end
    end
  end
end
