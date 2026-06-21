# frozen_string_literal: true

module Textus
  module Action
    class Accept < Base

      verb :accept
      summary "apply a queued proposal to its target zone; requires the author capability"
      surfaces :cli, :mcp
      cli "accept"
      arg :pending_key, String, required: true, positional: true, description: "the queued proposal's key"

      def self.call(container:, call:, pending_key:)
        env = container.compositor.read(pending_key)
        parsed = proposal_from(env, key: pending_key)
        target = parsed[:target_key]
        action = parsed[:proposal]["action"] || "put"

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
