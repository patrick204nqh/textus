module Textus
  module Surface
    module MCP
      class Projector
        def initialize(view_key: :default)
          @view_key = view_key
        end

        def dispatch(verb_name, inputs:, store:, role: Textus::Value::Role::AGENT)
          spec = Textus::Protocol::VerbRegistry.for(verb_name.to_sym)
          raise Textus::UsageError.new("unknown verb: #{verb_name}") unless spec

          bound = Textus::Protocol::Binder.inputs_from_wire(spec, inputs)
          store.public_send(verb_name.to_sym, **bound)
        end
      end
    end
  end
end
