module Textus
  module Protocol
    class StoreEngine
      module MovePipeline
        module CheckEtag
          def self.call(ctx, _deps)
            return ctx unless ctx.if_etag
            raise EtagMismatch.new(ctx.from_key, ctx.if_etag, ctx.etag_before) if ctx.etag_before != ctx.if_etag
            ctx
          end
        end
      end
    end
  end
end
