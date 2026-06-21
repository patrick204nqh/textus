# frozen_string_literal: true

module Textus
  module Action
    class Accept < Composite
      extend Textus::Contract::DSL

      verb :accept
      summary "apply a queued proposal to its target zone; requires the author capability"
      surfaces :cli, :mcp
      cli "accept"
      arg :pending_key, String, required: true, positional: true, description: "the queued proposal's key"

      def self.call(container:, call:, pending_key:)
        env = container.compositor.read(pending_key)
        proposal = env.meta["proposal"] or raise Textus::ProposalError.new("entry has no proposal block: #{pending_key}")
        target = proposal["target_key"] or raise Textus::ProposalError.new("proposal missing target_key")
        action = proposal["action"] || "put"

        case action
        when "put"
          mentry = container.manifest.resolver.resolve(target).entry
          container.compositor.write(
            target,
            mentry: mentry,
            payload: Textus::Store::Envelope::Writer::Payload.new(
              meta: env.meta["_meta"] || {},
              body: env.body,
              content: nil,
            ),
            call: call,
          )
        when "delete"
          container.compositor.delete(target, call: call)
        else
          raise Textus::ProposalError.new("unknown action: #{action}")
        end

        container.compositor.delete(pending_key, call: call)

        { "protocol" => Textus::PROTOCOL, "accepted" => pending_key, "target_key" => target, "action" => action,
          "cascade_key" => target }
      end
    end
  end
end
