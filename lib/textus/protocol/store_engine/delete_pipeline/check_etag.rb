module Textus
  module Protocol
    class StoreEngine
      module DeletePipeline
        module CheckEtag
          def self.call(ctx, deps)
            Pipeline.check_etag(ctx, deps)
          end
        end
      end
    end
  end
end
