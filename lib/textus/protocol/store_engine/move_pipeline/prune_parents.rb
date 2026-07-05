module Textus
  module Protocol
    class StoreEngine
      module MovePipeline
        module PruneParents
          def self.call(ctx, deps)
            Pipeline.prune_parents(ctx.from_path, deps)
            ctx
          end
        end
      end
    end
  end
end
