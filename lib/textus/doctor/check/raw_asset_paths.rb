module Textus
  module Doctor
    class Check
      class RawAssetPaths < Check
        def call
          raw_lane = manifest.policy.lanes_of_kind(:raw).first
          return [] unless raw_lane

          issues = []
          manifest.resolver.enumerate.each do |row|
            next unless row[:key].start_with?("raw.")
            next unless row[:path] && File.exist?(row[:path])

            raw_content = load_content(row[:path])
            next unless raw_content.is_a?(Hash)

            asset = raw_content["asset"]
            next unless asset.is_a?(String) && !asset.empty?

            asset_path = find_asset_path(asset)
            next if File.exist?(asset_path)

            issues << {
              "code" => "raw_asset.missing_file",
              "level" => "error",
              "subject" => row[:key],
              "message" => "raw entry '#{row[:key]}' references asset '#{asset}' " \
                           "which does not exist at #{asset_path}",
              "fix" => "re-ingest the asset: textus key-delete #{row[:key]}, then textus ingest",
            }
          end
          issues
        end

        private

        def load_content(path)
          require "yaml"
          YAML.safe_load_file(path)
        rescue StandardError
          nil
        end

        def find_asset_path(asset_rel)
          File.join(root, "assets", asset_rel)
        end
      end
    end
  end
end
