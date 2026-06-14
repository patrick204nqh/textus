# frozen_string_literal: true

module Textus
  module Surfaces
    # Role-scoped facade that dispatches through the Gate.
    # Replaces the old Event-based RoleScope.
    class RoleScope
      attr_reader :container, :role, :correlation_id

      def initialize(container:, role:, dry_run: false, correlation_id: nil)
        @container = container
        @role = role.to_s
        @dry_run = dry_run
        @correlation_id = correlation_id || SecureRandom.uuid
      end

      def dry_run? = !!@dry_run

      def with_role(role)
        self.class.new(container: @container, role:, dry_run: @dry_run, correlation_id: @correlation_id)
      end

      def with_correlation_id(cid)
        self.class.new(container: @container, role: @role, dry_run: @dry_run, correlation_id: cid)
      end

      def with_dry_run
        self.class.new(container: @container, role: @role, dry_run: true, correlation_id: @correlation_id)
      end

      def hook_context
        @hook_context ||= Textus::Step::Context.new(scope: self)
      end

      def dispatch_bound(verb, inputs, session: nil)
        cmd_class = Textus::Gate::VERB_COMMAND[verb]

        if cmd_class
          cmd = build_command(cmd_class, verb, inputs)
          [@container.gate.dispatch(cmd, container: @container, correlation_id: @correlation_id)]
        else
          action = build_action(verb, inputs, session)
          call = Textus::Call.build(role: @role, correlation_id: @correlation_id, dry_run: @dry_run)
          [action.call(container: @container, call: call)]
        end
      end

      private

      def build_command(cmd_class, verb, inputs)
        klass  = Textus::Action::VERBS[verb]
        spec   = klass.contract if klass.respond_to?(:contract?) && klass.contract?
        role_filter_param = spec&.args&.any? { |a| a.name == :role }

        role_value = if role_filter_param
                       inputs.key?(:role) ? inputs[:role] : nil
                     else
                       @role
                     end
        merged = inputs.merge(role: role_value)
        filled = cmd_class.members.to_h { |m| [m, merged.key?(m) ? merged[m] : nil] }
        cmd_class.new(**filled)
      end

      def build_action(verb, inputs, session)
        klass = Textus::Action::VERBS[verb]
        spec  = klass.contract if klass.respond_to?(:contract?) && klass.contract?

        if spec
          pos, kwargs = Textus::Contract::Binder.bind(spec, inputs, session: session)
          spec.args.select(&:positional).zip(pos).each { |a, v| kwargs[a.name] = v unless kwargs.key?(a.name) }
          klass.new(**kwargs)
        else
          klass.new(**inputs.transform_keys(&:to_sym))
        end
      end
    end
  end
end
