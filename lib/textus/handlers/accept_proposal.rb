module Textus
  module Handlers
    class AcceptProposal
      def initialize(compositor:)
        @compositor = compositor
      end

      def call(command, call)
        env = @compositor.read(command.pending_key)
        proposal = env&.meta&.dig("proposal") or
          return Result.failure(:proposal_error, "entry has no proposal block: #{command.pending_key}")
        target = proposal["target_key"] or
          return Result.failure(:proposal_error, "proposal missing target_key")
        action = proposal["action"] || "put"

        case action
        when "put"
          mentry = @compositor.manifest.resolver.resolve(target).entry
          @compositor.write(target, mentry: mentry,
            payload: Textus::Value::Payload.new(meta: env.meta["_meta"] || {}, body: env.body, content: nil),
            call: call)
        when "delete"
          @compositor.delete(target, call: call)
        else
          return Result.failure(:proposal_error, "unknown action: #{action}")
        end

        @compositor.delete(command.pending_key, call: call)
        Result.success("protocol" => Textus::PROTOCOL, "accepted" => command.pending_key,
                       "target_key" => target, "action" => action, "cascade_key" => target)
      end
    end
  end
end
