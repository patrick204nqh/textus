require "json"

module Textus
  module Doctor
    class Check
      class AuditLog < Check
        def call
          out = []
          path = File.join(store.root, "audit.log")
          return out unless File.exist?(path)

          File.foreach(path).with_index(1) do |line, lineno| # rubocop:disable Metrics/BlockLength
            stripped = line.chomp
            next if stripped.empty?

            if stripped.start_with?("{")
              begin
                JSON.parse(stripped)
              rescue JSON::ParserError => e
                out << {
                  "code" => "audit.parse_error",
                  "level" => "warning",
                  "subject" => "#{path}:#{lineno}",
                  "message" => "audit log line #{lineno} is invalid JSON: #{e.message}",
                  "fix" => "inspect #{path} at line #{lineno} and remove the corrupted row",
                }
              end
            else
              # Legacy TSV (pre-0.5): read-only support retained for on-disk logs
              # written by older textus versions. Never written by current code.
              # Minimum 6 fields.
              fields = stripped.split("\t")
              next if fields.length >= 6

              out << {
                "code" => "audit.parse_error",
                "level" => "warning",
                "subject" => "#{path}:#{lineno}",
                "message" => "audit log line #{lineno} has #{fields.length} fields " \
                             "(expected >=6 for legacy TSV; consider migrating to NDJSON)",
                "fix" => "inspect #{path} at line #{lineno} and remove the corrupted row",
              }
            end
          end
          out
        end
      end
    end
  end
end
