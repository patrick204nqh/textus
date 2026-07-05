module Textus
  module Protocol
    module Handlers
      module Ops
        class AuditFilter
          def call(ctx:, key: nil, lane: nil, role: nil, verb: nil, since: nil, seq_since: nil, correlation_id: nil, limit: nil)
            if seq_since
              min = ctx.audit_log.min_available
              raise Textus::CursorExpired.new(requested: seq_since, min_available: min) if min && seq_since < min - 1
            end

            rows = ctx.audit_log.list(seq_since:, key:, role:, verb:, correlation_id:, limit:).select do |row|
              next false if lane && !key_in_lane?(row["key"], lane, ctx)
              next false if since && row["ts"] && Time.parse(row["ts"]) < since

              true
            end
            { "verb" => "audit", "rows" => rows }
          end

          private

          def key_in_lane?(key, lane_name, ctx)
            mentry = ctx.mentry_for(key:)
            mentry && mentry.lane == lane_name
          rescue Textus::Error
            false
          end
        end
      end
    end
  end
end
