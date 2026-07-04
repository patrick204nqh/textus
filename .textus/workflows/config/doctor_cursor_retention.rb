# Warns/errors when persisted cursors are behind the retained audit sequence bounds.

# rubocop:disable Metrics/BlockLength
Textus.workflow "doctor-cursor-retention" do
  match "artifacts.doctor.cursor-retention"

  step :scan do |_, ctx|
    store = ctx.store
    issues = []
    roles = %w[automation human agent]
    min_available = store.event_store.min_available_seq

    roles.each do |role|
      cursor_seq = store.cursor_store.read(role)
      next if cursor_seq <= 0

      if min_available && cursor_seq < min_available
        issues << {
          "code" => "cursor.expired",
          "level" => "error",
          "subject" => "cursor:#{role}",
          "message" => "cursor for role '#{role}' (seq #{cursor_seq}) is no longer in the " \
                       "audit log (min available: #{min_available})",
          "fix" => "call pulse to get a fresh cursor",
        }
      end
    end

    { "content" => { "ok" => issues.empty?, "issues" => issues, "count" => issues.size } }
  end

  publish
end
# rubocop:enable Metrics/BlockLength
