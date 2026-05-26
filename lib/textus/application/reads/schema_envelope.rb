module Textus
  module Application
    module Reads
      class SchemaEnvelope
        def initialize(ctx:)
          @ctx = ctx
        end

        def call(key)
          mentry = @ctx.manifest.resolve(key).entry
          schema = @ctx.schemas.fetch_or_nil(mentry.schema)
          { "protocol" => PROTOCOL, "key" => key, "schema_ref" => mentry.schema, "schema" => schema&.to_h }
        end
      end
    end
  end
end
