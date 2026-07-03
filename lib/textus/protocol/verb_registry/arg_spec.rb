module Textus
  module Protocol
    module VerbRegistry
      ArgSpec = Data.define(
        :name, :type, :required, :positional, :session_default,
        :description, :wire_name, :default, :source, :coerce, :cli_default
      ) do
        def wire = wire_name || name
   
        # rubocop:disable Metrics/ParameterLists
        def self.arg(name:, type: String, required: false, positional: false,
                     session_default: nil, description: nil, wire_name: nil,
                     default: nil, source: nil, coerce: nil, cli_default: nil)
          new(name:, type:, required:, positional:, session_default:,
              description:, wire_name:, default:, source:, coerce:, cli_default:)
        end
        # rubocop:enable Metrics/ParameterLists
  end
  end
  end
  end
