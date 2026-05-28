require "json"
require "time"

module Textus
  module Application
    module Reads
      # Queries .textus/audit.log. Filters: key, zone, role, verb, since,
      # correlation_id, limit. Reads the log file as JSON-Lines (legacy TSV
      # rows produce nil and are skipped).
      module Audit
        def self.call(*, session:, ctx:, caps:, **) # rubocop:disable Lint/UnusedMethodArgument
          Impl.new(caps: caps).call(*, **)
        end

        def self.parse_since(str, now: Time.now.utc)
          Impl.parse_since(str, now: now)
        end

        class Impl
          def initialize(caps:)
            @manifest  = caps.manifest
            @root      = caps.root
            @log_path  = File.join(caps.root, "audit.log")
            @audit_log = caps.audit_log
          end

          # rubocop:disable Metrics/ParameterLists, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
          def call(key: nil, zone: nil, role: nil, verb: nil, since: nil, seq_since: nil, correlation_id: nil, limit: nil)
            check_cursor_expiry!(seq_since)

            files = all_log_files
            return [] if files.empty?

            rows = []
            files.each do |file|
              File.foreach(file) do |line|
                parsed = parse_row(line.chomp)
                next unless parsed
                next if key && parsed["key"] != key
                next if role && parsed["role"] != role
                next if verb && parsed["verb"] != verb
                next if zone && !key_in_zone?(parsed["key"], zone)
                next if since && (parsed["ts"].nil? || Time.parse(parsed["ts"]) < since)
                next if seq_since && (parsed["seq"].nil? || parsed["seq"] <= seq_since)
                next if correlation_id && parsed.dig("extras", "correlation_id") != correlation_id

                rows << parsed
                break if limit && rows.length >= limit
              end
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

          def check_cursor_expiry!(seq_since)
            return unless seq_since

            log = @audit_log || Textus::Infra::AuditLog.new(@root)
            min = log.min_available_seq
            raise Textus::CursorExpired.new(requested: seq_since, min_available: min) if min && seq_since < min - 1
          end

          def all_log_files
            rotated = Dir.glob(File.join(@root, "audit.log.*"))
                         .reject { |p| p.end_with?(".meta.json") }
                         .sort_by { |p| -p.scan(/\d+$/).first.to_i } # .5 .4 .3 .2 .1 → oldest first
            active = File.exist?(@log_path) ? [@log_path] : []
            rotated + active
          end

          def parse_row(line)
            return nil if line.empty?
            return nil unless line.start_with?("{")

            JSON.parse(line)
          rescue JSON::ParserError
            nil
          end

          def key_in_zone?(key, zone)
            mentry = @manifest.resolver.resolve(key).entry
            mentry && mentry.zone == zone
          rescue Textus::Error
            false
          end
        end
      end
    end
  end
end

Textus::Application::UseCase.register(:audit, Textus::Application::Reads::Audit, caps: :read)
