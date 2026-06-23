module Textus
  module Handlers
    class AcceptProposal
      def initialize(container:)
        @container = container
      end

      def call(command, call)
        env = @container.pipeline.read(command.pending_key)
        proposal = env&.meta&.dig("proposal") or
          return Value::Result.failure(:proposal_error, "entry has no proposal block: #{command.pending_key}")
        target = proposal["target_key"] or
          return Value::Result.failure(:proposal_error, "proposal missing target_key")
        action = proposal["action"] || "put"

        case action
        when "put"
          mentry = @container.manifest.resolver.resolve(target).entry
          @container.pipeline.write(
            target, mentry: mentry, call: call,
                    payload: Textus::Value::Payload.new(meta: env.meta["_meta"] || {}, body: env.body, content: nil)
          )
        when "delete"
          @container.pipeline.delete(target, call: call)
        else
          return Value::Result.failure(:proposal_error, "unknown action: #{action}")
        end

        @container.pipeline.delete(command.pending_key, call: call)
        Value::Result.success("protocol" => Textus::PROTOCOL, "accepted" => command.pending_key,
                       "target_key" => target, "action" => action, "cascade_key" => target)
      end
    end
  end
end
