Textus.workflow "doctor-cursor-retention" do
  match "artifacts.doctor.cursor-retention"

  step :scan do |_, ctx|
    store = ctx.container.store
    issues = []
    roles = %w[automation human agent]

    roles.each do |role|
      cursor = store.cursor_store.get(role)[:seq]
      next if cursor.nil? || cursor <= 0

      min_seq = store.audit_log.min_available
      if min_seq && cursor < min_seq
        issues << { "code" => "cursor.expired", "level" => "warning",
                    "subject" => "cursor:#{role}",
                    "message" => "cursor for role '#{role}' (seq #{cursor}) is no longer available",
                    "fix" => "call pulse to get a fresh cursor" }
      end
    end

    { "content" => { "ok" => issues.empty?, "issues" => issues, "count" => issues.size } }
  end

  publish
end
