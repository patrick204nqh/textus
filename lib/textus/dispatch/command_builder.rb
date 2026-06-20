module Textus
  module Dispatch
    # Builds a Gate::Command from resolved inputs per the contract spec.
    # Inputs must already be validated and defaults-resolved by Binder.bind.
    # CommandBuilder handles only member-mapping and role injection.
    module CommandBuilder
      module_function

      def build(spec, inputs, role:)
        Textus::Command.new(verb: spec.verb, params: inputs.freeze, role: role)
      end
    end
  end
end
