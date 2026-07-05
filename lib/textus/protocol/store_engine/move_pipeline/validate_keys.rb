module Textus
  module Protocol
    class StoreEngine
      module MovePipeline
        module ValidateKeys
          def self.call(ctx, _deps)
            Manifest::Data.validate_key!(ctx.from_key)
            Manifest::Data.validate_key!(ctx.to_key)
            raise UsageError.new("old and new keys are identical") if ctx.from_key == ctx.to_key
            ctx
          end
        end
      end
    end
  end
end
