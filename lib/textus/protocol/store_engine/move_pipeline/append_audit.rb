module Textus
  module Protocol
    class StoreEngine
      module MovePipeline
        module AppendAudit
          def self.call(ctx, deps)
            deps.audit_log.append(
              role: deps.call.role, verb: "key_mv", key: ctx.to_key,
              etag_before: ctx.etag_before, etag_after: ctx.etag_after,
              correlation_id: deps.call.correlation_id)
            ctx
          end
        end
      end
    end
  end
end
