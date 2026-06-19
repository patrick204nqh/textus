module Textus
  module Dispatch
    # Unified dispatch pipeline. Each surface performs its own transport-specific
    # normalization (wire-name mapping, stdin parsing, CLI defaults) to produce a
    # by-name `inputs` hash, then delegates the common sequence to this module:
    #
    #   1. Optionally wrap in an Around resource (cursor, build_lock)
    #   2. Resolve defaults and validate required args via Binder
    #   3. Build a Gate::Command via CommandBuilder
    #   4. Dispatch through the gate
    #
    # Surfaces apply their own view rendering afterward — the Dispatcher returns
    # the raw Gate result.
    module Dispatcher
      module_function

      def dispatch(spec, inputs, store:, role:, session: nil, scope: nil, correlation_id: nil)
        invoke = lambda do |effective_inputs|
          resolved = Binder.bind(spec, effective_inputs, session: session)
          cmd = CommandBuilder.build(spec, resolved, role: role)
          store.gate.dispatch(cmd, correlation_id: correlation_id)
        end

        if spec.around && scope
          Around.with(spec.around, scope: scope, inputs: inputs, session: session, &invoke)
        else
          invoke.call(inputs)
        end
      end
    end
  end
end
