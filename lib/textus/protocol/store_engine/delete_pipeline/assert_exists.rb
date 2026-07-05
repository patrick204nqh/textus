module Textus
  module Protocol
    class StoreEngine
      module DeletePipeline
        module AssertExists
          def self.call(ctx, deps)
            return ctx if deps.file_system.exists?(ctx.path)
            raise Textus::UnknownKey.new(ctx.key, suggestions: deps.manifest.resolver.suggestions_for(ctx.key))
          end
        end
      end
    end
  end
end
