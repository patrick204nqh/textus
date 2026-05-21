require "digest"
require "json"

module Textus
  module Doctor
    class Check
      class Sentinels < Check
        def call
          out = []
          dir = File.join(store.root, "sentinels")
          return out unless File.directory?(dir)

          Dir.glob(File.join(dir, "**", "*.textus-managed.json")).each do |sp| # rubocop:disable Metrics/BlockLength
            begin
              data = JSON.parse(File.read(sp))
            rescue JSON::ParserError => e
              out << {
                "code" => "sentinel.parse_error",
                "level" => "warning",
                "subject" => sp,
                "message" => "sentinel is not valid JSON: #{e.message}",
                "fix" => "delete #{sp} and re-run 'textus build' to regenerate",
              }
              next
            end

            target = data["target"]
            recorded_sha = data["sha256"]

            if target.nil? || !File.exist?(target)
              out << {
                "code" => "sentinel.orphan",
                "level" => "warning",
                "subject" => sp,
                "message" => "sentinel target #{target.inspect} no longer exists",
                "fix" => "delete #{sp} (the published file is gone) or restore the target",
              }
              next
            end

            current_sha = Digest::SHA256.hexdigest(File.binread(target))
            next if recorded_sha.nil? || current_sha == recorded_sha

            out << {
              "code" => "sentinel.drift",
              "level" => "warning",
              "subject" => target,
              "message" => "published file at #{target} was modified out-of-band",
              "fix" => "re-run 'textus build' to overwrite, or copy the manual edit back into the store source",
            }
          end
          out
        end
      end
    end
  end
end
