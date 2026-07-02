# frozen_string_literal: true

module Textus
  module UseCases
    module Ops
      class SchemaEnvelope < Base
        handles Dispatch::Contracts::SchemaEnvelope
        needs :manifest, :schemas

        def call
          mentry = manifest.resolver.resolve(command.key).entry
          schema = schemas.fetch_or_nil(mentry.schema)
          success("protocol" => Textus::PROTOCOL, "key" => command.key,
                  "schema_ref" => mentry.schema, "schema" => schema&.to_h)
        end
      end
    end
  end
end
