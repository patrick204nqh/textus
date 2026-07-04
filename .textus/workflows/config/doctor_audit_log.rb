Textus.workflow "doctor-audit-log" do
  match "artifacts.doctor.audit-log"

  step :scan do |_, ctx|
    store = ctx.container.store
    issues = []
    latest = store.audit_log.latest

    if latest.nil?
      issues << { "code" => "audit.empty", "level" => "info", "subject" => "audit",
                  "message" => "audit log is empty", "fix" => nil }
    end

    { "content" => { "ok" => issues.empty?, "issues" => issues, "count" => issues.size } }
  end

  publish
end
