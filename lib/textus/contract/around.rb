module Textus
  module Contract
    # Registry of named, stateful wrappers a verb may declare via `around :name`.
    # A resource implements
    #   `wrap(scope:, inputs:, session:) { |effective_inputs| ... }`:
    # it may adjust the inputs before the call and post-process the result after
    # — exactly what build's lock and pulse's cursor need, without a hand-authored
    # CLI class (ADR 0068). `session:` is the dispatching session (nil for the
    # sessionless CLI/Ruby surfaces, present for MCP), so a session-aware resource
    # like the cursor can defer to the session's own state instead of its file.
    module Around
      @registry = {}

      module_function

      def register(name, resource)
        @registry[name] = resource
      end

      def fetch(name)
        @registry.fetch(name) { raise "no around resource registered: #{name.inspect}" }
      end

      def with(name, scope:, inputs:, session: nil, &call)
        fetch(name).wrap(scope: scope, inputs: inputs, session: session, &call)
      end
    end
  end
end
