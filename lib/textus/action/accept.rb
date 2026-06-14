# frozen_string_literal: true

module Textus
  module Action
    class Accept < WriteVerb
      extend Textus::Contract::DSL

      verb :accept
      summary "apply a queued proposal to its target zone; requires the author capability"
      surfaces :cli, :mcp
      cli "accept"
      arg :pending_key, String, required: true, positional: true, description: "the queued proposal's key"

      BURN = :sync

      def initialize(pending_key:)
        super()
        @pending_key = pending_key
      end

      def args
        { pending_key: @pending_key }
      end

      def call(container:, call:)
        env = Textus::Action::Get.new(key: @pending_key).call(container: container, call: call)
        proposal = env.meta["proposal"] or raise Textus::ProposalError.new("entry has no proposal block: #{@pending_key}")
        target = proposal["target_key"] or raise Textus::ProposalError.new("proposal missing target_key")
        action = proposal["action"] || "put"

        case action
        when "put"
          Textus::Action::Put.new(
            key: target,
            meta: env.meta["_meta"] || {},
            body: env.body,
          ).call(container: container, call: call)
        when "delete"
          Textus::Action::KeyDelete.new(key: target).call(container: container, call: call)
        else
          raise Textus::ProposalError.new("unknown action: #{action}")
        end

        Textus::Action::KeyDelete.new(key: @pending_key).call(container: container, call: call)

        container.steps.publish(
          :proposal_accepted,
          ctx: Textus::Step::Context.for(container: container, call: call),
          key: @pending_key,
          target_key: target,
        )

        { "protocol" => Textus::PROTOCOL, "accepted" => @pending_key, "target_key" => target, "action" => action }
      end
    end
  end
end
