# frozen_string_literal: true

module Textus
  module Action
    class Reject < WriteVerb
      extend Textus::Contract::DSL

      verb :reject
      summary "discard a queued proposal without applying it"
      surfaces :cli, :mcp
      cli "reject"
      arg :pending_key, String, required: true, positional: true, description: "the queued proposal's key"

      BURN = :sync

      def initialize(pending_key:)
        super()
        @pending_key = pending_key
      end

      def call(container:, call:)
        run_with_cascade(@pending_key, container:, call:) do
          auth = Textus::Gate::Auth.new(container)
          auth.check_action!(action: :reject, actor: call.role, key: @pending_key)

          mentry = container.manifest.resolver.resolve(@pending_key).entry
          unless mentry.in_proposal_lane?(container.manifest.policy)
            raise ProposalError.new("reject: '#{@pending_key}' is not in a proposal zone (zone=#{mentry.lane})")
          end

          env = Textus::Action::Get.new(key: @pending_key).call(container: container, call: call)
          proposal = env.meta&.dig("proposal") or raise ProposalError.new("entry has no proposal block: #{@pending_key}")
          target_key = proposal["target_key"] or raise ProposalError.new("proposal missing target_key")

          writer(container, call).delete(@pending_key, mentry: mentry)

          container.steps.publish(
            :proposal_rejected,
            ctx: Textus::Step::Context.for(container: container, call: call),
            key: @pending_key,
            target_key: target_key,
          )

          { "protocol" => PROTOCOL, "rejected" => @pending_key, "target_key" => target_key }
        end
      end
    end
  end
end
