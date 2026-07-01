module Textus
  module Doctor
    class Check
      # Warns when a persisted cursor points into the oldest retained audit
      # rotation (at risk of being dropped on the next rotation). Errors when
      # a cursor seq has already been rotated out.
      class CursorRetention < Check
        def call
          issues = []

          Dir.glob(File.join(root, ".state", "ephemeral", "cursors", "*")).each do |cursor_path|
            role = File.basename(cursor_path)
            cursor_seq = Integer(File.read(cursor_path).strip) rescue next
            next if cursor_seq <= 0

            audit_log = Port::AuditLog.new(root, layout: geometry,
                                            keep: manifest.data.audit_config[:keep])
            min_avail = audit_log.send(:min_available_seq)

            if min_avail && cursor_seq < min_avail
              issues << expired_issue(role, cursor_seq, min_avail)
              next
            end

            keep = manifest.data.audit_config[:keep]
            oldest_meta_path = geometry.audit_rotated_meta_path(keep)
            if File.exist?(oldest_meta_path)
              meta = JSON.parse(File.read(oldest_meta_path)) rescue nil
              if meta && cursor_seq >= meta["min_seq"] && cursor_seq <= meta["max_seq"]
                issues << at_risk_issue(role, cursor_seq, meta["min_seq"], meta["max_seq"])
              end
            end
          end

          issues
        rescue Errno::ENOENT
          []
        end

        private

        def expired_issue(role, cursor_seq, min_avail)
          {
            "code" => "cursor.expired",
            "level" => "error",
            "subject" => "cursor:#{role}",
            "message" => "cursor for role '#{role}' (seq #{cursor_seq}) is no longer in the " \
                         "audit log (min available: #{min_avail})",
            "fix" => "increase audit.keep in the manifest or call pulse to get a fresh cursor",
          }
        end

        def at_risk_issue(role, cursor_seq, oldest_min, oldest_max)
          {
            "code" => "cursor.at_risk",
            "level" => "warning",
            "subject" => "cursor:#{role}",
            "message" => "cursor for role '#{role}' (seq #{cursor_seq}) is in the oldest " \
                         "retained audit rotation (#{oldest_min}..#{oldest_max}); the next " \
                         "rotation will drop it",
            "fix" => "increase audit.keep in the manifest or call pulse more frequently",
          }
        end
      end
    end
  end
end
