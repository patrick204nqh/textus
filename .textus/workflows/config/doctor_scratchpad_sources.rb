# Replaces Doctor::Check::ScratchpadSources. Warns when scratchpad notes
# reference raw source keys that no longer resolve.

# rubocop:disable Metrics/BlockLength
Textus.workflow "doctor-scratchpad-sources" do
  match "artifacts.doctor.scratchpad-sources"

  step :scan do |_, ctx|
    issues = []

    ctx.manifest.resolver.enumerate.each do |row|
      next unless row[:key].start_with?("scratchpad.notes.")
      next unless row[:path] && File.exist?(row[:path])

      content = begin
        File.read(row[:path])
      rescue StandardError
        nil
      end
      next if content.nil?

      match = content.match(/\A---\n(.*?)\n---/m)
      next if match.nil?

      front = begin
        YAML.safe_load(match[1])
      rescue StandardError
        nil
      end

      sources = Array(front&.dig("sources")).filter_map do |source|
        case source
        when String then source
        when Hash then source["key"]
        end
      end

      sources.each do |raw_key|
        exists = begin
          path = ctx.manifest.resolver.resolve(raw_key).path
          File.exist?(path)
        rescue Textus::UnknownKey, Textus::Error
          false
        end
        next if exists

        issues << {
          "code" => "scratchpad.source_missing",
          "level" => "warning",
          "subject" => row[:key],
          "message" => "scratchpad entry '#{row[:key]}' references raw key '#{raw_key}' which does not exist in the store",
          "fix" => "re-ingest the source: textus ingest ..., or remove the stale sources: entry",
        }
      end
    end

    { "content" => { "ok" => issues.empty?, "issues" => issues, "count" => issues.size } }
  end

  publish
end
# rubocop:enable Metrics/BlockLength
