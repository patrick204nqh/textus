module Textus
  module UseCases
    module Write
      class AcceptProposal < Base
        handles Dispatch::Contracts::AcceptProposal
        needs :file_system, :manifest, :audit_log, :layout, :writer, :reader

        def call
          env = reader.read(command.pending_key)
          parsed = extract_proposal(env, command.pending_key)
          return parsed if parsed.failure?

          target = parsed.value[:target]
          action = parsed.value[:action]

          return dry_run_preview(target, env, action) if command.dry_run

          exec_and_cleanup(target, action, env)
        end

        private

        def extract_proposal(env, pending_key)
          proposal = env&.meta&.dig("proposal") or
            return failure(:proposal_error, "entry has no proposal block: #{pending_key}")
          target = proposal["target_key"] or
            return failure(:proposal_error, "proposal missing target_key")

          success({ target: target, action: proposal["action"] || "put" })
        end

        def dry_run_preview(target, env, action)
          target_env = reader.read(target)
          body_diff = Textus::Diff.body(target_env&.body, env.body)
          meta_diff = Textus::Diff.meta(target_env&.meta&.dig("_meta") || {}, env.meta&.dig("_meta") || {})
          result = { "dry_run" => true, "pending_key" => command.pending_key, "target_key" => target, "action" => action }
          result["body"] = body_diff if body_diff
          result["meta"] = meta_diff if meta_diff
          result["summary"] = Textus::Diff.summary(result)
          success(result)
        end

        def exec_and_cleanup(target, action, env)
          case action
          when "put"
            mentry = manifest.resolver.resolve(target).entry
            writer.put(
              target, mentry: mentry, call: call,
                      payload: Textus::Value::Payload.new(meta: env.meta["_meta"] || {}, body: env.body, content: nil)
            )
          when "delete"
            writer.delete(target, call: call)
          else
            return failure(:proposal_error, "unknown action: #{action}")
          end

          writer.delete(command.pending_key, call: call)
          success("protocol" => Textus::PROTOCOL, "accepted" => command.pending_key,
                   "target_key" => target, "action" => action, "cascade_key" => target)
        end
      end
    end
  end
end
