module Textus
  module Protocol
    class StoreEngine
      module MovePipeline
        module EmitWorkflowEvent
          def self.call(ctx, deps)
            Pipeline.emit_event(ctx, deps,
                                event_type: "entry.moved", pending_key: ctx.from_key,
                                emit_key: ctx.to_key, emit_lane: ctx.to_entry.lane,
                                pending_keys: [ctx.from_key, ctx.to_key])
          end
        end
      end
    end
  end
end
