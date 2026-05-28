# frozen_string_literal: true

module Textus
  module Hooks
    # A narrow handle passed to user hooks in place of the raw Store.
    # All writes route back through the Session so authorization, audit
    # logging, and schema validation always fire.
    class Context
      attr_reader :role, :correlation_id

      def initialize(session:)
        @session = session
        @role = session.ctx.role
        @correlation_id = session.ctx.correlation_id
      end

      # read
      def get(key)                = @session.get(key)
      def list(**)                = @session.list(**)
      def deps(key)               = @session.deps(key)
      def freshness(key)          = @session.freshness(key)

      # write (authorized + audited)
      def put(key, **)          = @session.put(key, **)
      def delete(key, **)       = @session.delete(key, **)
      def audit(verb, key:, **) = @session.write_caps.audit_log.append(role: @role, verb: verb, key: key, **)

      # fan-out
      def publish_followup(event, **)
        @session.write_caps.events.publish(event, ctx: self, **)
      end

      def inspect
        "#<Textus::Hooks::Context role=#{@role} correlation_id=#{@correlation_id}>"
      end
    end
  end
end
