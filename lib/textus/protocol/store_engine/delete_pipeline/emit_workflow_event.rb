module Textus
  module Protocol
    class StoreEngine
      module DeletePipeline
        module EmitWorkflowEvent
          def self.call(ctx, deps)
            Pipeline.emit_event(ctx, deps,
                                event_type: "entry.deleted", pending_key: ctx.key,
                                emit_key: ctx.key)
          end
        end
      end
    end
  end
end
