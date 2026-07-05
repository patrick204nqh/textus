module Textus
  module Protocol
    class StoreEngine
      module MovePipeline
        module ReadEtagAfter
          def self.call(ctx, _deps)
            ctx.with(etag_after: Value::Etag.for_file(ctx.to_path))
          end
        end
      end
    end
  end
end
