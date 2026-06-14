# frozen_string_literal: true

module Textus
  module Surfaces
    # Role-scoped identity carrier. Holds the acting identity (role,
    # correlation_id, dry_run) bound to a container. All verb methods
    # (put, get, accept, ...) are injected by textus.rb's define_method
    # loop, which dispatches directly through Gate.
    class RoleScope
      attr_reader :container, :role, :correlation_id

      def initialize(container:, role:, dry_run: false, correlation_id: nil)
        @container      = container
        @role           = role.to_s
        @dry_run        = dry_run
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
    end
  end
end
