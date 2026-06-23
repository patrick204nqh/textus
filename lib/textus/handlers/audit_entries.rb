module Textus
  module Handlers
    class AuditEntries
      def initialize(manifest:, audit_log:)
        @manifest = manifest
        @audit_log = audit_log
      end

      def call(command, _call)
        cursor_check = check_cursor_expiry(command.seq_since)
        return cursor_check if cursor_check

        rows = @audit_log.scan(
          seq_since: command.seq_since,
          key: command.key, role: command.role, verb: command.verb,
          correlation_id: command.correlation_id, limit: command.limit
        ).select do |row|
          next false if command.lane && !key_in_lane?(row["key"], command.lane)
          next false if command.since && (row["ts"].nil? || Time.parse(row["ts"]) < command.since)

          true
        end
        Value::Result.success(rows)
      end

      private

      def check_cursor_expiry(seq_since)
        return unless seq_since

        min = @audit_log.min_available_seq
        return unless min && seq_since < min - 1

        Value::Result.failure(:cursor_expired, "requested seq #{seq_since} is below minimum available #{min}",
                       details: { requested: seq_since, min_available: min })
      end

      def key_in_lane?(key, lane)
        mentry = @manifest.resolver.resolve(key).entry
        mentry && mentry.lane == lane
      rescue Textus::Error
        false
      end
    end
  end
end
