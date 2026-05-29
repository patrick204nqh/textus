module Textus
  module Application
    module Read
      class SchemaEnvelope
        def initialize(container:, call: nil, hook_context: nil) # rubocop:disable Lint/UnusedMethodArgument
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
end

Textus::Application::UseCase.register(:schema_envelope, Textus::Application::Read::SchemaEnvelope, caps: :read)
