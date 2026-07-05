module Textus
  module Protocol
    class StoreEngine
      module MovePipeline
        module RewriteBasename
          def self.call(ctx, _deps)
            basename = ctx.to_key.split(".").last
            Format.for(ctx.to_entry.format).rewrite_name(ctx.to_path, basename)
            ctx
          end
        end
      end
    end
  end
end
