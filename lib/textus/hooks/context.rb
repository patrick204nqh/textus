# frozen_string_literal: true

module Textus
  module Hooks
    # A narrow handle passed to user hooks in place of the raw Store.
    # All writes route back through the Session so authorization, audit
    # logging, and schema validation always fire.
    class Context
      attr_reader :role, :correlation_id

      def initialize(session: nil, scope: nil)
        @session = session
        @scope   = scope
        if session
          @role = session.ctx.role
          @correlation_id = session.ctx.correlation_id
        elsif scope
          @role = scope.role
          @correlation_id = scope.correlation_id
        end
      end

      def backend
        @session || @scope
      end

      # read
      def get(key)                = backend.get(key)
      def list(**)                = backend.list(**)
      def deps(key)               = backend.deps(key)
      def freshness(key)          = backend.freshness(key)

      # write (authorized + audited)
      def put(key, **)          = backend.put(key, **)
      def delete(key, **)       = backend.delete(key, **)

      def audit(verb, key:, **)
        log = @session ? @session.write_caps.audit_log : @scope.container.audit_log
        log.append(role: @role, verb: verb, key: key, **)
      end

      # fan-out
      def publish_followup(event, **)
        bus = @session ? @session.write_caps.events : @scope.container.events
        bus.publish(event, ctx: self, **)
      end

      def inspect
        "#<Textus::Hooks::Context role=#{@role} correlation_id=#{@correlation_id}>"
      end
    end
  end
end
