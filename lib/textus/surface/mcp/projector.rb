module Textus
  module Surface
    module MCP
      class Projector
        def initialize(view_key: :default)
          @view_key = view_key
        end

        def dispatch(verb_name, inputs:, store:)
          spec = VerbRegistry.for(verb_name.to_sym)
          raise Textus::UsageError.new("unknown verb: #{verb_name}") unless spec

          bound = Textus::Dispatch::Binder.inputs_from_wire(spec, inputs)
          domain = Textus::VerbRegistry::VERB_DOMAIN.fetch(verb_name.to_sym) do
            raise Textus::UsageError.new("#{verb_name} has no domain assignment")
          end
          result = store.public_send(domain, verb_name.to_sym, **bound)
          spec.view(@view_key).call(result, bound)
        end
      end
    end
  end
end
