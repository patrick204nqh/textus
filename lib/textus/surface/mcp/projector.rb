module Textus
  module Surface
    module MCP
      class Projector
        def initialize(view_key: :default, binder_method: :inputs_from_wire)
          @view_key = view_key
          @binder_method = binder_method
        end

        def dispatch(verb_name, inputs:, store:)
          spec = VerbRegistry.for(verb_name.to_sym)
          raise Textus::UsageError.new("unknown verb: #{verb_name}") unless spec

          bound = Textus::Dispatch::Binder.public_send(@binder_method, spec, inputs)
          result = store.public_send(verb_name.to_sym, **bound)
          spec.view(@view_key).call(result, bound)
        end
      end
    end
  end
end
