module Textus
  module Protocol
    class StoreEngine
      module DeletePipeline
        module AppendAudit
          def self.call(ctx, deps)
            deps.audit_log.append(
              role: deps.call.role, verb: "key_delete", key: ctx.key,
              etag_before: ctx.etag_before, etag_after: nil,
              correlation_id: deps.call.correlation_id
            )
            ctx
          end
        end
      end
    end
  end
end
