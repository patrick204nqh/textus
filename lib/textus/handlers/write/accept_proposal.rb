module Textus
  module Handlers
    module Write
      module AcceptProposal
        HANDLES = Dispatch::Contracts::AcceptProposal
        NEEDS   = %i[file_store manifest schemas audit_log layout event_bus].freeze

        def self.call(command, call, deps)
          reader = Store::Entry::Reader.new(file_store: deps.file_store, manifest: deps.manifest, layout: deps.layout)
          env = reader.read(command.pending_key)
          proposal = env&.meta&.dig("proposal") or
            return Value::Result.failure(:proposal_error, "entry has no proposal block: #{command.pending_key}")
          target = proposal["target_key"] or
            return Value::Result.failure(:proposal_error, "proposal missing target_key")
          action = proposal["action"] || "put"

          writer = Store::Entry::Writer.new(
            file_store: deps.file_store, manifest: deps.manifest,
            schemas: deps.schemas, audit_log: deps.audit_log,
            call: call, reader: reader, layout: deps.layout
          )
          case action
          when "put"
            mentry = deps.manifest.resolver.resolve(target).entry
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
          if deps.respond_to?(:event_bus) && deps.event_bus
            deps.event_bus.emit(Textus::Event::ProposalAccepted.new(
                                  proposal_key: command.pending_key,
                                  target_key: target,
                                  role: call.role,
                                  occurred_at: call.now,
                                ))
          end
          Value::Result.success("protocol" => Textus::PROTOCOL, "accepted" => command.pending_key,
                                "target_key" => target, "action" => action, "cascade_key" => target)
        end
      end
    end
  end
end
