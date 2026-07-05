module Textus
  module Protocol
    class StoreEngine
      module MovePipeline
        module ResolvePaths
          def self.call(ctx, deps)
            from_result = deps.manifest.resolver.resolve(ctx.from_key)
            to_result   = deps.manifest.resolver.resolve(ctx.to_key)
            ctx.with(from_path: from_result.path, to_path: to_result.path,
                     from_entry: from_result.entry, to_entry: to_result.entry)
          end
        end
      end
    end
  end
end
