# Validates audit event store health.

Textus.workflow "doctor-audit-log" do
  match "artifacts.doctor.audit-log"

  step :scan do |_, ctx|
    store = ctx.store
    issues = []
    latest = store.event_store.latest_seq
    first = store.event_store.min_available_seq

    if latest == 0
      issues << {
        "code" => "audit.empty",
        "level" => "info",
        "subject" => "audit",
        "message" => "audit log is empty",
        "fix" => nil,
      }
    elsif first.nil?
      issues << {
        "code" => "audit.unavailable",
        "level" => "error",
        "subject" => "audit",
        "message" => "no events available despite latest_seq=#{latest}",
        "fix" => "check database integrity",
      }
    end

    { "content" => { "ok" => issues.empty?, "issues" => issues, "count" => issues.size } }
  end

  publish
end
