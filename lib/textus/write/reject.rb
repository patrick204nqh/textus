require_relative "authority_gate"

module Textus
  module Write
    class Reject
      include AuthorityGate

      def initialize(container:, call:, hook_context:)
        @container    = container
        @call         = call
        @ctx          = call # AuthorityGate uses @ctx.role
        @manifest     = container.manifest
        @events       = container.events
        @hook_context = hook_context
      end

      def call(pending_key)
        assert_accept_authority!("reject")

        mentry = @manifest.resolver.resolve(pending_key).entry
        unless mentry.in_proposal_zone?(@manifest.policy)
          raise ProposalError.new("reject: '#{pending_key}' is not in a proposal zone (zone=#{mentry.zone})")
        end

        env = Textus::Read::Get.new(
          container: @container, call: @call,
        ).call(pending_key)
        proposal = env.meta&.dig("proposal") or
          raise ProposalError.new("entry has no proposal block: #{pending_key}")
        target_key = proposal["target_key"] or
          raise ProposalError.new("proposal missing target_key")

        delete_op.call(pending_key, suppress_events: true)

        @events.publish(:proposal_rejected,
                        ctx: @hook_context,
                        key: pending_key,
                        target_key: target_key)

        { "protocol" => PROTOCOL, "rejected" => pending_key, "target_key" => target_key }
      end

      private

      def delete_op
        @delete_op ||= Textus::Write::Delete.new(
          container: @container, call: @call, hook_context: @hook_context,
        )
      end
    end
  end
end
