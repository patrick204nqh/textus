module Textus
  module Read
    class SchemaEnvelope
      extend Textus::Contract::DSL

      verb     :schema_show
      summary  "Return the schema (field shape) for an entry's family, by key."
      surfaces :cli, :mcp
      cli      "schema show"
      arg :key, String, required: true, positional: true,
                        description: "any key in the family whose schema you want; returns required/optional fields and their types"

      def initialize(container:, call: nil) # rubocop:disable Lint/UnusedMethodArgument
        @manifest = container.manifest
        @schemas  = container.schemas
      end

      def call(key)
        mentry = @manifest.resolver.resolve(key).entry
        schema = @schemas.fetch_or_nil(mentry.schema)
        { "protocol" => PROTOCOL, "key" => key, "schema_ref" => mentry.schema, "schema" => schema&.to_h }
      end
    end
  end
end
