module Textus
  module Protocol
    class StoreEngine
      module MovePipeline
        module ReadEnvelope
          def self.call(ctx, deps)
            envelope = deps.reader.read(key: ctx.to_key)
            ctx.with(envelope:)
          end
        end
      end
    end
  end
end
