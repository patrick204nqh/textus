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
        return parsed if parsed.is_a?(Dry::Monads::Result::Failure)

        target = parsed[:target_key]
        action = parsed[:proposal]["action"] || "put"

        case action
        when "put"
          mentry = container.manifest.resolver.resolve(target).entry
          container.compositor.write(
            target,
            mentry: mentry,
            payload: Textus::Value::Payload.new(
              meta: env.meta["_meta"] || {},
              body: env.body,
              content: nil,
            ),
            call: call,
          )
        when "delete"
          container.compositor.delete(target, call: call)
        else
          return Failure(code: :proposal_error, message: "unknown action: #{action}")
        end

        container.compositor.delete(pending_key, call: call)

        Success("protocol" => Textus::PROTOCOL, "accepted" => pending_key, "target_key" => target, "action" => action,
                "cascade_key" => target)
      end
    end
  end
end
