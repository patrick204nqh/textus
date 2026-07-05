module Textus
  module Protocol
    class StoreEngine
      module MovePipeline
        module AssertTargetNotExists
          def self.call(ctx, deps)
            return ctx unless ctx.to_path && deps.file_system.exists?(ctx.to_path)

            raise UsageError.new("target '#{ctx.to_key}' already exists")
          end
        end
      end
    end
  end
end
