# frozen_string_literal: true

module Textus
  module Dispatch
    module Actions
      class SchemaEnvelope < Base
        extend Textus::Contract::DSL

        verb :schema_show
        summary "Return the schema (field shape) for an entry's family, by key."
        surfaces :cli, :mcp
        cli "schema show"
        arg :key, String, required: true, positional: true,
                          description: "any key in the family whose schema you want; returns required/optional fields and their types"

        BURN = :sync

        def initialize(key:)
          super()
          @key = key
        end

        def args
          { key: @key }
        end

        def call(container:, **)
          manifest = container.manifest
          schemas = container.schemas
          mentry = manifest.resolver.resolve(@key).entry
          schema = schemas.fetch_or_nil(mentry.schema)
          { "protocol" => PROTOCOL, "key" => @key, "schema_ref" => mentry.schema, "schema" => schema&.to_h }
        end
      end
    end
  end
end
