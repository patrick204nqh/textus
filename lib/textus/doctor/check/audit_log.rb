module Textus
  module Doctor
    class Check
      class AuditLog < Check
        def call
          path = StoreGeometry.new(root).audit_log_path
          Textus::Port::AuditLog.new(root).verify_integrity.map do |v|
            {
              "code" => "audit.parse_error",
              "level" => "warning",
              "subject" => "#{path}:#{v["lineno"]}",
              "message" => violation_message(v),
              "fix" => "inspect #{path} at line #{v["lineno"]} and remove the corrupted row",
            }
          end
        end

        private

        def violation_message(v)
          case v["reason"]
          when "invalid_json"
            "audit log line #{v["lineno"]} is invalid JSON: #{v["detail"]}"
          when "short_tsv"
            "audit log line #{v["lineno"]} #{v["detail"]} " \
            "(consider migrating to NDJSON)"
          else
            v["detail"]
          end
        end
      end
    end
  end
end
