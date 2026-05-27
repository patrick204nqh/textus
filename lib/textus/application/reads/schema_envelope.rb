module Textus
  module Application
    module Reads
      class SchemaEnvelope
        def initialize(manifest:, schemas:)
          @manifest = manifest
          @schemas = schemas
        end

        def call(key)
          mentry = @manifest.resolver.resolve(key).entry
          schema = @schemas.fetch_or_nil(mentry.schema)
          { "protocol" => PROTOCOL, "key" => key, "schema_ref" => mentry.schema, "schema" => schema&.to_h }
        end
      end
    end
  end
end
