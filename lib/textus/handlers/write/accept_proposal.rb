module Textus
  module Handlers
    module Write
      class AcceptProposal
        def initialize(container:)
          @container = container
        end

        def call(command, call)
          reader = Store::Entry::Reader.from(container: @container)
          env = reader.read(command.pending_key)
          proposal = env&.meta&.dig("proposal") or
            return Value::Result.failure(:proposal_error, "entry has no proposal block: #{command.pending_key}")
          target = proposal["target_key"] or
            return Value::Result.failure(:proposal_error, "proposal missing target_key")
          action = proposal["action"] || "put"

          writer = Store::Entry::Writer.from(container: @container, call: call)
          case action
          when "put"
            mentry = @container.manifest.resolver.resolve(target).entry
            writer.put(
              target, mentry: mentry,
                      payload: Textus::Value::Payload.new(meta: env.meta["_meta"] || {}, body: env.body, content: nil)
            )
          when "delete"
            writer.delete(target)
          else
            return Value::Result.failure(:proposal_error, "unknown action: #{action}")
          end

          writer.delete(command.pending_key)
          Value::Result.success("protocol" => Textus::PROTOCOL, "accepted" => command.pending_key,
                                "target_key" => target, "action" => action, "cascade_key" => target)
        end
      end
    end
  end
end
