module Textus
  module Protocol
    class StoreEngine
      module MovePipeline
        module ReadEtagBefore
          def self.call(ctx, deps)
            ctx.with(etag_before: deps.file_system.etag(ctx.from_path))
          end
        end
      end
    end
  end
end
