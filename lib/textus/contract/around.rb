module Textus
  module Contract
    # Registry of named, stateful wrappers a verb may declare via `around :name`.
    # A resource implements `wrap(scope:, inputs:) { |effective_inputs| ... }`:
    # it may adjust the inputs before the call and post-process the result
    # after — exactly what build's lock and pulse's cursor need, without a
    # hand-authored CLI class (ADR 0068).
    module Around
      @registry = {}

      module_function

      def register(name, resource)
        @registry[name] = resource
      end

      def fetch(name)
        @registry.fetch(name) { raise "no around resource registered: #{name.inspect}" }
      end

      def with(name, scope:, inputs:, &call)
        fetch(name).wrap(scope: scope, inputs: inputs, &call)
      end
    end
  end
end
