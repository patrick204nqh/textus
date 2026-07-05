module Textus
  module Protocol
    class StoreEngine
      module DeletePipeline
        module DeindexEntry
          def self.call(ctx, deps)
            deps.entry_index.remove(key: ctx.key)
            ctx
          end
        end
      end
    end
  end
end
