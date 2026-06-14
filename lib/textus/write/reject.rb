module Textus
  module Write
    class Reject
      extend Textus::Contract::DSL

      verb :reject
      summary "discard a queued proposal without applying it"
      surfaces :cli, :mcp
      cli "reject"
      arg :pending_key, String, required: true, positional: true, description: "the queued proposal's key"

      def initialize(container:, call:)
        @container    = container
        @call         = call
        @manifest     = container.manifest
        @schemas      = container.schemas
        @steps = container.steps
      end

      def call(pending_key)
        auth.check!(action: :reject, actor: @call.role, key: pending_key)

        mentry = @manifest.resolver.resolve(pending_key).entry
        unless mentry.in_proposal_zone?(@manifest.policy)
          raise ProposalError.new("reject: '#{pending_key}' is not in a proposal zone (zone=#{mentry.lane})")
        end

        env = Textus::Read::Get.new(
          container: @container, call: @call,
        ).call(pending_key)
        proposal = env.meta&.dig("proposal") or
          raise ProposalError.new("entry has no proposal block: #{pending_key}")
        target_key = proposal["target_key"] or
          raise ProposalError.new("proposal missing target_key")

        delete_op.call(pending_key, suppress_events: true)

        @steps.publish(:proposal_rejected,
                       ctx: hook_context,
                       key: pending_key,
                       target_key: target_key)

        { "protocol" => PROTOCOL, "rejected" => pending_key, "target_key" => target_key }
      end

      private

      def auth
        @auth ||= Textus::Dispatch::Auth.new(manifest: @manifest, schemas: @schemas)
      end

      def hook_context
        @hook_context ||= Textus::Step::Context.for(container: @container, call: @call)
      end

      def delete_op
        @delete_op ||= Textus::Write::KeyDelete.new(
          container: @container, call: @call,
        )
      end
    end
  end
end
