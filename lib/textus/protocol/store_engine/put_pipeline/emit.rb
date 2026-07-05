module Textus
  module Protocol
    class StoreEngine
      module PutPipeline
        module Emit
          def self.call(ctx, deps)
            ctx = append_audit(ctx, deps)
            ctx = index_entry(ctx, deps)
            emit_workflow_event(ctx, deps)
          end

          def self.append_audit(ctx, deps)
            deps.audit_log.append(
              role: deps.call.role, verb: "put", key: ctx.key,
              etag_before: ctx.etag_before, etag_after: ctx.envelope.etag,
              correlation_id: deps.call.correlation_id
            )
            ctx
          end

          def self.index_entry(ctx, deps)
            content = ctx.eff_content ? ctx.eff_content.to_json : ctx.eff_body
            deps.entry_index.record(
              key: ctx.key, lane: ctx.mentry.lane, format: ctx.format,
              schema: ctx.mentry.schema, content: content
            )
            ctx
          end

          def self.emit_workflow_event(ctx, deps)
            Pipeline.emit_event(ctx, deps,
                                event_type: "entry.written", pending_key: ctx.key,
                                emit_key: ctx.key, emit_lane: ctx.mentry.lane)
          end
        end
      end
    end
  end
end
