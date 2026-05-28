module Textus
  module Application
    module Reads
      module SchemaEnvelope
        def self.call(*, session:, ctx:, caps:, **) # rubocop:disable Lint/UnusedMethodArgument
          Impl.new(caps: caps).call(*, **)
        end

        class Impl
          def initialize(caps:)
            @manifest = caps.manifest
            @schemas  = caps.schemas
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
end

Textus::Application::UseCase.register(:schema_envelope, Textus::Application::Reads::SchemaEnvelope, caps: :read)
