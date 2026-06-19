module Textus
  module Dispatch
    # Builds a Gate::Command from resolved inputs per the contract spec.
    # Inputs must already be validated and defaults-resolved by Binder.bind.
    # CommandBuilder handles only member-mapping and role injection.
    module CommandBuilder
      module_function

      def build(spec, inputs, role:)
        cmd_class = Textus::Gate::VERB_COMMAND.fetch(spec.verb) do
          raise Textus::UsageError.new("no Command for verb: #{spec.verb}")
        end

        inputs = inputs.dup
        inputs[:role] = role if cmd_class.members.include?(:role) && !inputs.key?(:role)

        filled = cmd_class.members.to_h { |m| [m, inputs.key?(m) ? inputs[m] : nil] }
        cmd_class.new(**filled)
      end
    end
  end
end
