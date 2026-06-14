# frozen_string_literal: true

module Textus
  module Step
    # A narrow handle passed to user steps in place of the raw Store.
    # All writes route back through the RoleScope so authorization, audit
    # logging, and schema validation always fire.
    class Context
      attr_reader :role, :correlation_id

      def self.for(container:, call:)
        scope = Textus::Surfaces::RoleScope.new(
          container: container,
          role: call.role,
          correlation_id: call.correlation_id,
          dry_run: call.dry_run,
        )
        new(scope: scope)
      end

      def initialize(scope:)
        @scope          = scope
        @role           = scope.role
        @correlation_id = scope.correlation_id
      end

      def backend
        @scope
      end

      # read — a pure-observation surface: nothing here ingests. Since ADR 0089
      # `get` itself is a pure read (the read-through that once forced this
      # surface to opt out is gone, so the old re-entrancy/deadlock guard is no
      # longer needed); `list`/`deps`/`freshness` are reads too. A hook observes
      # current state and never triggers an I/O cascade.
      def get(key)                = pure_reader.call(key)
      def list(**)                = @scope.list(**)
      def deps(key)               = @scope.deps(key)
      def freshness(key)          = @scope.freshness(key)

      # write (authorized + audited)
      def put(key, **)          = @scope.put(key, **)
      def delete(key, **)       = @scope.key_delete(key, **)

      def audit(verb, key:, **)
        @scope.container.audit_log.append(role: @role, verb: verb, key: key, **)
      end

      # fan-out
      def publish_followup(event, **)
        @scope.container.steps.publish(event, ctx: self, **)
      end

      def inspect
        "#<Textus::Step::Context role=#{@role} correlation_id=#{@correlation_id}>"
      end

      private

      def pure_reader
        @pure_reader ||= lambda do |key|
          Textus::Action::Get.new(key: key).call(
            container: @scope.container,
            call: Textus::Call.build(
              role: @scope.role,
              correlation_id: @scope.correlation_id,
              dry_run: @scope.dry_run?,
            ),
          )
        end
      end
    end
  end
end
