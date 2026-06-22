# frozen_string_literal: true

module Textus
  module Action
    class SchemaEnvelope < Base
      verb :schema_show
      summary "Return the schema (field shape) for an entry's family, by key."
      surfaces :cli, :mcp
      cli "schema show"
      arg :key, String, required: true, positional: true,
                        description: "any key in the family whose schema you want; returns required/optional fields and their types"

      def self.call(container:, key:, **)
        manifest = container.manifest
        schemas = container.schemas
        mentry = manifest.resolver.resolve(key).entry
        schema = schemas.fetch_or_nil(mentry.schema)
        Success({ "protocol" => Textus::PROTOCOL, "key" => key, "schema_ref" => mentry.schema, "schema" => schema&.to_h })
      end
    end
  end
end
