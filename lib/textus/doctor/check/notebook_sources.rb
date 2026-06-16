module Textus
  module Doctor
    class Check
      class NotebookSources < Check
        def call
          issues = []
          manifest.resolver.enumerate.each do |row|
            next unless row[:key].start_with?("notebook.notes.")
            next unless row[:path] && File.exist?(row[:path])

            sources = parse_sources(row[:path])
            sources.each do |raw_key|
              next if raw_entry_exists?(raw_key)

              issues << {
                "code" => "notebook.source_missing",
                "level" => "warning",
                "subject" => row[:key],
                "message" => "notebook entry '#{row[:key]}' references raw key '#{raw_key}' " \
                             "which does not exist in the store",
                "fix" => "re-ingest the source: textus ingest ..., or remove the stale sources: entry",
              }
            end
          end
          issues
        end

        private

        def parse_sources(path)
          content = File.read(path)
          match = content.match(/\A---\n(.*?)\n---/m)
          return [] unless match

          front = YAML.safe_load(match[1])
          Array(front&.dig("sources"))
        rescue StandardError
          []
        end

        def raw_entry_exists?(key)
          path = manifest.resolver.resolve(key).path
          File.exist?(path)
        rescue Textus::UnknownKey, Textus::Error
          false
        end
      end
    end
  end
end
