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
        @events       = container.events
      end

      def call(pending_key)
        guard.for(:reject, pending_key).check!(
          Textus::Domain::Policy::Evaluation.new(
            actor: @call.role, transition: :reject, origin: pending_key,
            target: pending_key, envelope: nil, manifest: @manifest
          ),
        )

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
                        ctx: hook_context,
                        key: pending_key,
                        target_key: target_key)

        { "protocol" => PROTOCOL, "rejected" => pending_key, "target_key" => target_key }
      end

      private

      def guard
        @guard ||= Textus::Domain::Policy::GuardFactory.new(manifest: @manifest, schemas: @schemas)
      end

      def hook_context
        @hook_context ||= Textus::Hooks::Context.for(container: @container, call: @call)
      end

      def delete_op
        @delete_op ||= Textus::Write::Delete.new(
          container: @container, call: @call,
        )
      end
    end
  end
end
