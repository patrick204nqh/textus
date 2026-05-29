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

    # NOTE: #dry_run is overridden below to return a *new* RoleScope.
    # Use instance_variable_get(:@dry_run) (or #dry_run?) to read the flag.

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

    def dry_run
      self.class.new(container: @container, role: @role, dry_run: true, correlation_id: @correlation_id)
    end

    # Boot/Doctor convenience — Store#as(role).boot / .doctor.
    def boot(**) = Textus::Boot.run_via(container: @container, role: @role, **)
    def doctor(**) = Textus::Doctor.run_via(container: @container, role: @role, **)

    Textus::Dispatcher::VERBS.each_key do |verb|
      define_method(verb) do |*args, **kwargs|
        klass = Textus::Dispatcher.fetch(verb)
        call_value = Textus::Call.build(
          role: @role, correlation_id: @correlation_id, dry_run: @dry_run,
        )
        params = klass.instance_method(:initialize).parameters.map { |_, n| n }
        init_kwargs = { container: @container, call: call_value }
        init_kwargs[:hook_context] = Textus::Hooks::Context.new(scope: self) if params.include?(:hook_context)
        klass.new(**init_kwargs).call(*args, **kwargs)
      end
    end
  end
end
