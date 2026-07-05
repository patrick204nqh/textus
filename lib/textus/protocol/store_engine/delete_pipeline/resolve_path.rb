module Textus
  module Protocol
    class StoreEngine
      module DeletePipeline
        module ResolvePath
          def self.call(ctx, deps)
            ctx.with(path: Pipeline.resolve_path(ctx.key, deps))
          end
        end
      end
    end
  end
end
