module Textus
  # Thin role-scoped facade over a Container. Closes over a role default
  # and a dry_run flag, then forwards every verb in Dispatcher::VERBS to
  # the corresponding use case.
  #
  # Replaces the per-call Session under the 0.27.0 architecture: a Store
  # exposes #as(role) to get a RoleScope, and Store#put / Store#get / etc
  # delegate to RoleScope under the default role.
  class RoleScope
    attr_reader :container, :role, :correlation_id

    def dry_run?
      @dry_run
    end

    def initialize(container:, role:, dry_run: false, correlation_id: nil)
      @container = container
      @role      = role.to_s
      @dry_run   = dry_run
      @correlation_id = correlation_id
    end

    def with_role(role)
      self.class.new(container: @container, role: role, dry_run: @dry_run, correlation_id: @correlation_id)
    end

    def with_correlation_id(cid)
      self.class.new(container: @container, role: @role, dry_run: @dry_run, correlation_id: cid)
    end

    def hook_context
      @hook_context ||= Textus::Hooks::Context.new(scope: self)
    end

    def with_dry_run
      self.class.new(container: @container, role: @role, dry_run: true, correlation_id: @correlation_id)
    end

    # Single bind + invoke site for every surface. `inputs` is the uniform
    # by-name hash (the binder's currency). MCP/CLI build it from their raw
    # transport shape and call this directly; the per-verb Ruby methods below
    # normalize positional+keyword Ruby args into `inputs` and delegate here.
    def dispatch_bound(verb, inputs, session: nil)
      klass = Textus::Dispatcher::VERBS[verb]
      spec = (klass.contract if klass.respond_to?(:contract?) && klass.contract?)

      invoke = lambda do |effective_inputs|
        args, kwargs =
          if spec
            Textus::Contract::Binder.bind(spec, effective_inputs, session: session)
          else
            [[], effective_inputs]
          end
        call_value = Textus::Call.build(role: @role, correlation_id: @correlation_id, dry_run: @dry_run)
        Textus::Dispatcher.invoke(verb, container: @container, call: call_value, args: args, kwargs: kwargs)
      end

      if spec&.around
        Textus::Contract::Around.with(spec.around, scope: self, inputs: inputs, session: session, &invoke)
      else
        invoke.call(inputs)
      end
    end

    Textus::Dispatcher::VERBS.each_key do |verb|
      define_method(verb) do |*args, **kwargs|
        klass = Textus::Dispatcher::VERBS[verb]
        inputs =
          if klass.respond_to?(:contract?) && klass.contract?
            Textus::Contract::Binder.inputs_from_ordered(klass.contract, args, kwargs)
          else
            kwargs
          end
        dispatch_bound(verb, inputs)
      end
    end
  end
end
