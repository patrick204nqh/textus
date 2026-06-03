module Textus
  module Contract
    # Renders a use-case result for a surface, using the verb's declared view
    # (falling back to the default). The single replacement for the old
    # response/cli_response split and the Proc#arity sniff: views are always
    # called as (result, inputs); a one-parameter view ignores inputs.
    module View
      module_function

      def render(spec, surface, result, inputs)
        spec.view(surface).call(result, inputs)
      end
    end
  end
end
