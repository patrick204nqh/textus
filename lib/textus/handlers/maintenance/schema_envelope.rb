module Textus
  module Handlers
    module Maintenance
      module SchemaEnvelope
        HANDLES = Dispatch::Contracts::SchemaEnvelope
        NEEDS   = %i[manifest schemas].freeze

        def self.call(command, _call, deps)
          mentry = deps.manifest.resolver.resolve(command.key).entry
          schema = deps.schemas.fetch_or_nil(mentry.schema)
          Value::Result.success("protocol" => Textus::PROTOCOL, "key" => command.key,
                                "schema_ref" => mentry.schema, "schema" => schema&.to_h)
        end
      end
    end
  end
end
