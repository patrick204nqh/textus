module Textus
  module UseCases
    module Write
      module AcceptProposal
        HANDLES = Dispatch::Contracts::AcceptProposal
        NEEDS = %i[file_store manifest schemas audit_log layout event_bus].freeze

        def self.call(command, call, deps)
          reader = Store::Entry::Reader.new(file_store: deps.file_store, manifest: deps.manifest, layout: deps.layout)
          env = reader.read(command.pending_key)
          parsed = extract_proposal(env, command.pending_key)
          return parsed if parsed.failure?

          target = parsed.value[:target]
          action = parsed.value[:action]

          return dry_run_preview(reader, target, env, command, action) if command.dry_run

          exec_and_cleanup(target, action, env, reader, deps, call, command, parsed)
        end

        def self.extract_proposal(env, pending_key)
          proposal = env&.meta&.dig("proposal") or
            return Value::Result.failure(:proposal_error, "entry has no proposal block: #{pending_key}")
          target = proposal["target_key"] or
            return Value::Result.failure(:proposal_error, "proposal missing target_key")

          Value::Result.success({ target: target, action: proposal["action"] || "put" })
        end
        private_class_method :extract_proposal

        def self.dry_run_preview(reader, target, env, command, action)
          target_env = reader.read(target)
          body_diff = Textus::Diff.body(target_env&.body, env.body)
          meta_diff = Textus::Diff.meta(target_env&.meta&.dig("_meta") || {}, env.meta&.dig("_meta") || {})
          result = { "dry_run" => true, "pending_key" => command.pending_key, "target_key" => target, "action" => action }
          result["body"] = body_diff if body_diff
          result["meta"] = meta_diff if meta_diff
          result["summary"] = Textus::Diff.summary(result)
          Value::Result.success(result)
        end
        private_class_method :dry_run_preview

        def self.exec_and_cleanup(target, action, env, reader, deps, call, command, _parsed)
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
        private_class_method :exec_and_cleanup
      end
    end
  end
end
