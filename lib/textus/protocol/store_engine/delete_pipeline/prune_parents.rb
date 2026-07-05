module Textus
  module Protocol
    class StoreEngine
      module DeletePipeline
        module PruneParents
          def self.call(ctx, deps)
            Pipeline.prune_parents(ctx.path, deps)
            ctx
          end
        end
      end
    end
  end
end
