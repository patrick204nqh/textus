module Textus
  module Protocol
    class StoreEngine
      module MovePipeline
        module ReindexEntry
          def self.call(ctx, deps)
            deps.entry_index.remove(key: ctx.from_key)
            content = ctx.envelope.content ? ctx.envelope.content.to_json : ctx.envelope.body
            deps.entry_index.record(
              key: ctx.to_key, lane: ctx.to_entry.lane, format: ctx.to_entry.format,
              schema: ctx.to_entry.schema, content: content)
            ctx
          end
        end
      end
    end
  end
end
