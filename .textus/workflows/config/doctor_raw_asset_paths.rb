# Replaces Doctor::Check::RawAssetPaths. Verifies raw entries that declare an
# asset path still point to an existing file under assets/.

# rubocop:disable Metrics/BlockLength
Textus.workflow "doctor-raw-asset-paths" do
  match "artifacts.doctor.raw-asset-paths"

  step :scan do |_, ctx|
    raw_lane = ctx.manifest.policy.lanes_of_kind(:raw).first
    issues = []

    unless raw_lane.nil?
      ctx.manifest.resolver.enumerate.each do |row|
        next unless row[:key].start_with?("raw.")
        next unless row[:path] && File.exist?(row[:path])

        raw_content = begin
          YAML.safe_load_file(row[:path])
        rescue StandardError
          nil
        end
        next unless raw_content.is_a?(Hash)

        asset = raw_content["asset"]
        next unless asset.is_a?(String) && !asset.empty?

        asset_path = File.join(ctx.layout.root, "assets", asset)
        next if File.exist?(asset_path)

        issues << {
          "code" => "raw_asset.missing_file",
          "level" => "error",
          "subject" => row[:key],
          "message" => "raw entry '#{row[:key]}' references asset '#{asset}' which does not exist at #{asset_path}",
          "fix" => "re-ingest the asset: textus key-delete #{row[:key]}, then textus ingest",
        }
      end
    end

    { "content" => { "ok" => issues.empty?, "issues" => issues, "count" => issues.size } }
  end

  publish
end
# rubocop:enable Metrics/BlockLength
