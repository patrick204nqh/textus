module Textus
  module Protocol
    class StoreEngine
      module MovePipeline
        module AssertSourceExists
          def self.call(ctx, deps)
            return ctx if deps.file_system.exists?(ctx.from_path)
            raise UnknownKey.new(ctx.from_key, suggestions: deps.manifest.resolver.suggestions_for(ctx.from_key))
          end
        end
      end
    end
  end
end
