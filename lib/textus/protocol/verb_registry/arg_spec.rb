module Textus
  module Protocol
    module VerbRegistry
      ArgSpec = Data.define(
        :name, :type, :required, :positional,
        :description, :wire_name, :default, :source, :coerce, :cli_default
      ) do
        def wire = wire_name || name

        def self.arg(name:, type: String, required: false, positional: false,
                     description: nil, wire_name: nil,
                     default: nil, source: nil, coerce: nil, cli_default: nil)
          new(name:, type:, required:, positional:,
              description:, wire_name:, default:, source:, coerce:, cli_default:)
        end
      end
    end
  end
end
