# Replaces Doctor::Check::CursorRetention. Warns/errors when persisted cursors
# are inside or behind retained audit sequence bounds.

# rubocop:disable Metrics/BlockLength
Textus.workflow "doctor-cursor-retention" do
  match "artifacts.doctor.cursor-retention"

  step :scan do |_, ctx|
    issues = []
    cursor_glob = File.join(ctx.container.root, ".state", "ephemeral", "cursors", "*")

    Dir.glob(cursor_glob).each do |cursor_path|
      role = File.basename(cursor_path)
      cursor_seq = begin
        Integer(File.read(cursor_path).strip)
      rescue StandardError
        nil
      end
      next if cursor_seq.nil? || cursor_seq <= 0

      audit_log = Textus::Protocol::Audit.new(
        ctx.container.root,
        layout: ctx.container.layout,
        keep: ctx.container.manifest.data.audit_config[:keep],
      )

      min_available = audit_log.send(:min_available_seq)
      if min_available && cursor_seq < min_available
        issues << {
          "code" => "cursor.expired",
          "level" => "error",
          "subject" => "cursor:#{role}",
          "message" => "cursor for role '#{role}' (seq #{cursor_seq}) is no longer in the " \
                       "audit log (min available: #{min_available})",
          "fix" => "increase audit.keep in the manifest or call pulse to get a fresh cursor",
        }
        next
      end

      keep = ctx.container.manifest.data.audit_config[:keep]
      oldest_meta_path = ctx.container.layout.audit_rotated_meta_path(keep)
      next unless File.exist?(oldest_meta_path)

      meta = begin
        JSON.parse(File.read(oldest_meta_path))
      rescue StandardError
        nil
      end
      next unless meta && cursor_seq >= meta["min_seq"] && cursor_seq <= meta["max_seq"]

      issues << {
        "code" => "cursor.at_risk",
        "level" => "warning",
        "subject" => "cursor:#{role}",
        "message" => "cursor for role '#{role}' (seq #{cursor_seq}) is in the oldest " \
                     "retained audit rotation (#{meta["min_seq"]}..#{meta["max_seq"]}); the next " \
                     "rotation will drop it",
        "fix" => "increase audit.keep in the manifest or call pulse more frequently",
      }
    end

    { "content" => { "ok" => issues.empty?, "issues" => issues, "count" => issues.size } }
  end

  publish
end
# rubocop:enable Metrics/BlockLength
