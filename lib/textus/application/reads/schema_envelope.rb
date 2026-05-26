module Textus
  module Application
    module Reads
      class SchemaEnvelope
        def initialize(ctx:)
          @ctx = ctx
        end

        def call(key)
          @ctx.store.reader.schema_envelope(key)
        end
      end
    end
  end
end
