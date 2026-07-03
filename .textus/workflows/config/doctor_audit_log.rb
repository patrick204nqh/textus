# Replaces Doctor::Check::AuditLog. Validates active audit log integrity.

Textus.workflow "doctor-audit-log" do
  match "artifacts.doctor.audit-log"

  step :scan do |_, ctx|
    path = Textus::Protocol::Layout.new(ctx.container.root).audit_log_path
    issues = Textus::Protocol::Audit.new(ctx.container.root).verify_integrity.map do |v|
      detail = case v["reason"]
               when "invalid_json"
                 "audit log line #{v["lineno"]} is invalid JSON: #{v["detail"]}"
               when "short_tsv"
                 "audit log line #{v["lineno"]} #{v["detail"]} (consider migrating to NDJSON)"
               else
                 v["detail"]
               end

      {
        "code" => "audit.parse_error",
        "level" => "warning",
        "subject" => "#{path}:#{v["lineno"]}",
        "message" => detail,
        "fix" => "inspect #{path} at line #{v["lineno"]} and remove the corrupted row",
      }
    end

    { "content" => { "ok" => issues.empty?, "issues" => issues, "count" => issues.size } }
  end

  publish
end
