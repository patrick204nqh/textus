module Textus
  module Handlers
    class SchemaEnvelope
      def initialize(manifest:, schemas:)
        @manifest = manifest
        @schemas = schemas
      end

      def call(command, call)
        mentry = @manifest.resolver.resolve(command.key).entry
        schema = @schemas.fetch_or_nil(mentry.schema)
        Result.success("protocol" => Textus::PROTOCOL, "key" => command.key,
                       "schema_ref" => mentry.schema, "schema" => schema&.to_h)
      end
    end
  end
end
