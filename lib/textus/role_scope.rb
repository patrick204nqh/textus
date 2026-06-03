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

    Textus::Dispatcher::VERBS.each_key do |verb|
      define_method(verb) do |*args, **kwargs|
        klass = Textus::Dispatcher::VERBS[verb]
        if klass.respond_to?(:contract?) && klass.contract?
          klass.contract.args.each do |a|
            next if a.positional || a.default.nil? || kwargs.key?(a.name)

            kwargs[a.name] = a.default
          end
        end
        call_value = Textus::Call.build(
          role: @role, correlation_id: @correlation_id, dry_run: @dry_run,
        )
        Textus::Dispatcher.invoke(
          verb, container: @container, call: call_value, args: args, kwargs: kwargs
        )
      end
    end
  end
end
