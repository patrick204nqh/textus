# frozen_string_literal: true

module Textus
  module Hooks
    # A narrow handle passed to user hooks in place of the raw Store.
    # All writes route back through Operations so authorization, audit
    # logging, and schema validation always fire.
    class Context
      attr_reader :role, :correlation_id

      def initialize(ops:)
        @ops = ops
        @role = ops.ctx.role
        @correlation_id = ops.ctx.correlation_id
      end

      # read
      def get(key)                = @ops.get(key)
      def list(**)                = @ops.list(**)
      def deps(key)               = @ops.deps(key)
      def freshness(key)          = @ops.freshness(key)

      # write (authorized + audited)
      def put(key, **)          = @ops.put(key, **)
      def delete(key, **)       = @ops.delete(key, **)
      def audit(verb, key:, **) = @ops.write_caps.audit_log.append(role: @role, verb: verb, key: key, **)

      # fan-out
      def publish_followup(event, **)
        @ops.write_caps.events.publish(event, ctx: self, **)
      end

      def inspect
        "#<Textus::Hooks::Context role=#{@role} correlation_id=#{@correlation_id}>"
      end
    end
  end
end
