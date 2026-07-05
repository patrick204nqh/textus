module Textus
  module Protocol
    module Handlers
      module Ops
        class AuditFilter
          FILTER_KEYS = %i[key lane role verb since seq_since correlation_id limit].freeze

          def call(ctx:, filters: {})
            seq = filters[:seq_since]
            if seq
              min = ctx.audit_log.min_available
              raise Textus::CursorExpired.new(requested: seq, min_available: min) if min && seq < min - 1
            end

            rows = ctx.audit_log.list(seq_since: filters[:seq_since], key: filters[:key], role: filters[:role], verb: filters[:verb],
                                      correlation_id: filters[:correlation_id], limit: filters[:limit]).select do |row|
              next false if filters[:lane] && !key_in_lane?(row["key"], filters[:lane], ctx)
              next false if filters[:since] && row["ts"] && Time.parse(row["ts"]) < filters[:since]

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
