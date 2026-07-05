module Textus
  module Protocol
    class StoreEngine
      module DeletePipeline
        module DeleteFile
          def self.call(ctx, deps)
            deps.file_system.delete(ctx.path)
            ctx
          end
        end
      end
    end
  end
end
