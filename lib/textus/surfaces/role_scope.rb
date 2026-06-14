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
        klass = Textus::Action::VERBS[verb]
        spec = (klass.contract if klass.respond_to?(:contract?) && klass.contract?)
        if spec
          _, kwargs = Textus::Contract::Binder.bind(spec, inputs, session: session)
          action = klass.new(**kwargs)
        else
          sym_inputs = inputs.transform_keys(&:to_sym)
          action = klass.new(**sym_inputs)
        end
        call = Textus::Call.build(role: @role, correlation_id: @correlation_id, dry_run: @dry_run)
        [action.call(container: @container, call:)]
      end
    end
  end
end
