module Textus
  module Protocol
    module Handlers
      module Ops
        class PulseCoordinator
          def call(role:, ctx:, since: nil)
            cursor_val = since || ctx.cursor_store.get(role)[:seq]
            audit_filter = AuditFilter.new
            audit_result = audit_filter.call(ctx:, filters: { seq_since: cursor_val })
            changed = audit_result["rows"] || []
            queue = ctx.manifest.policy.queue_lane
            pending = queue ? ctx.list(lane: queue) : []
            runner = Textus::Lanes::Knowledge::Runner.new(ctx.manifest, cursor_store: ctx.cursor_store)
            result = {
              "cursor" => ctx.audit_log.latest[:seq],
              "changed" => changed,
              "pending_review" => pending.is_a?(Array) ? pending.map { |r| r["key"] } : [],
              "contract_etag" => Textus::Value::Etag.for_contract(ctx.layout),
              "index_etag" => pulse_index_etag(ctx),
              "loop_state" => runner.current_position(role),
            }
            ctx.cursor_store.set(role, result["cursor"])
            result
          end

          private

          def pulse_index_etag(ctx)
            ctx.etag_for("artifacts.system.index")
          rescue Textus::Error
            nil
          end
        end
      end
    end
  end
end
