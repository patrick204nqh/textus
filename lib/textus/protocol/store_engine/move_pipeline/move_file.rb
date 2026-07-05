module Textus
  module Protocol
    class StoreEngine
      module MovePipeline
        module MoveFile
          def self.call(ctx, deps)
            deps.file_system.mv(ctx.from_path, ctx.to_path)
            ctx
          end
        end
      end
    end
  end
end
