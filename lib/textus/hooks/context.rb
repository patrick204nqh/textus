# frozen_string_literal: true

module Textus
  module Hooks
    # A narrow handle passed to user hooks in place of the raw Store.
    # All writes route back through the RoleScope so authorization, audit
    # logging, and schema validation always fire.
    class Context
      attr_reader :role, :correlation_id

      def self.for(container:, call:)
        scope = Textus::RoleScope.new(
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

      # read — a deliberately pure-observation surface: NOTHING here fetches
      # (`list`/`deps`/`freshness` don't either). The invariant is that a hook
      # observes current state and never triggers an I/O cascade. `get` bypasses
      # the read-through behavior (ADR 0062) and reads with fetch:false directly,
      # because read-through inside a hook would: (1) fire fetch events → hooks →
      # unbounded reentrancy; (2) spawn the orchestrator's threads/fork from
      # inside a hook callback; (3) probe the single-flight fetch lock its own
      # enclosing fetch may hold (deadlock); (4) inject network latency into
      # every hook read. With the merged Read::Get class, `fetch:false` (the
      # method default) guarantees no orchestrator is built.
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
        @scope.container.events.publish(event, ctx: self, **)
      end

      def inspect
        "#<Textus::Hooks::Context role=#{@role} correlation_id=#{@correlation_id}>"
      end

      private

      def pure_reader
        @pure_reader ||= Textus::Read::Get.new(
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
