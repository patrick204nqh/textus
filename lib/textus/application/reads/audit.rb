require "json"
require "time"

module Textus
  module Application
    module Reads
      # Queries .textus/audit.log. Filters: key, zone, role, verb, since,
      # correlation_id, limit. Reads the log file as JSON-Lines (legacy TSV
      # rows produce nil and are skipped).
      class Audit
        def initialize(manifest:, root:)
          @manifest = manifest
          @log_path = File.join(root, "audit.log")
        end

        # rubocop:disable Metrics/ParameterLists, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
        def call(key: nil, zone: nil, role: nil, verb: nil, since: nil, correlation_id: nil, limit: nil)
          return [] unless File.exist?(@log_path)

          rows = []
          File.foreach(@log_path) do |line|
            parsed = parse_row(line.chomp)
            next unless parsed
            next if key   && parsed["key"]  != key
            next if role  && parsed["role"] != role
            next if verb  && parsed["verb"] != verb
            next if zone  && !key_in_zone?(parsed["key"], zone)
            next if since && (parsed["ts"].nil? || Time.parse(parsed["ts"]) < since)
            next if correlation_id && parsed.dig("extras", "correlation_id") != correlation_id

            rows << parsed
            break if limit && rows.length >= limit
          end
          rows
        end
        # rubocop:enable Metrics/ParameterLists, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

        # Accepts ISO8601 ("2026-01-15", "2026-01-15T10:00:00Z") or a relative
        # offset matching /\A(\d+)([smhd])\z/. Returns nil for unparseable input.
        def self.parse_since(str, now: Time.now.utc)
          return nil if str.nil? || str.empty?
          return Time.parse(str) if str =~ /\A\d{4}-\d{2}-\d{2}/

          m = str.match(/\A(\d+)([smhd])\z/) or return nil
          mult = { "s" => 1, "m" => 60, "h" => 3600, "d" => 86_400 }[m[2]]
          now - (m[1].to_i * mult)
        end

        private

        def parse_row(line)
          return nil if line.empty?
          return nil unless line.start_with?("{")

          JSON.parse(line)
        rescue JSON::ParserError
          nil
        end

        def key_in_zone?(key, zone)
          mentry = @manifest.resolve(key).entry
          mentry && mentry.zone == zone
        rescue Textus::Error
          false
        end
      end
    end
  end
end
