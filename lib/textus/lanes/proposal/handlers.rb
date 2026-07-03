module Textus
  module Lanes
    module Proposal
      module Handlers
        module_function
  
        def propose(key:, ctx:, call:, meta: nil, body: nil, content: nil)
          zone = ctx.manifest.policy.propose_lane_for(call.role)
          return { error: { code: "propose_forbidden", message: "role '#{call.role}' has no writable propose_lane" } } unless zone
  
          full_key = "#{zone}.#{key}"
          mentry = ctx.mentry_for(full_key)
          env = ctx.write(
            full_key, mentry:, call:,
                      payload: ctx.payload(meta: meta || {}, body:, content:)
          )
          env.to_h_for_wire
        end
  
        def accept(pending_key:, ctx:, call:, dry_run: false)
          env = ctx.read(pending_key)
          proposal = env&.meta&.dig("proposal")
          return { error: { code: "proposal_error", message: "entry has no proposal block: #{pending_key}" } } unless proposal
  
          target = proposal["target_key"]
          return { error: { code: "proposal_error", message: "proposal missing target_key" } } unless target
  
          action = proposal["action"] || "put"
  
          if dry_run
            target_env = ctx.read(target)
            body_diff = Textus::Protocol::Diff.body(target_env&.body, env.body)
            meta_diff = Textus::Protocol::Diff.meta(target_env&.meta&.dig("_meta") || {}, env.meta&.dig("_meta") || {})
            result = { "dry_run" => true, "pending_key" => pending_key, "target_key" => target, "action" => action }
            result["body"] = body_diff if body_diff
            result["meta"] = meta_diff if meta_diff
            result["summary"] = Textus::Protocol::Diff.summary(result)
            return result
          end
  
          case action
          when "put"
            mentry = ctx.mentry_for(target)
            ctx.write(target, mentry:, call:,
                                 payload: ctx.payload(meta: env.meta["_meta"] || {}, body: env.body, content: nil))
          when "delete"
            ctx.delete(target, call:)
          else
            return { error: { code: "proposal_error", message: "unknown action: #{action}" } }
          end
  
          ctx.delete(pending_key, call:)
          { "protocol" => Textus::PROTOCOL, "accepted" => pending_key,
            "target_key" => target, "action" => action, "cascade_key" => target }
        end
  
        def reject(pending_key:, ctx:, call:, reason: nil)
          mentry = ctx.mentry_for(pending_key)
          unless mentry.in_proposal_lane?(ctx.manifest.policy)
            return { error: { code: "proposal_error", message: "reject: '#{pending_key}' is not in a proposal zone (zone=#{mentry.lane})" } }
          end
  
          env = ctx.read(pending_key)
          proposal = env&.meta&.dig("proposal")
          return { error: { code: "proposal_error", message: "entry has no proposal block: #{pending_key}" } } unless proposal
  
          target_key = proposal["target_key"]
          ctx.delete(pending_key, mentry:, call:)
          result = { "protocol" => Textus::PROTOCOL, "rejected" => pending_key, "target_key" => target_key }
          result["reason"] = reason if reason
          result
        end
  
        def diff(pending_key:, ctx:, call:)
          env = ctx.read(pending_key)
          proposal = env&.meta&.dig("proposal")
          return { error: { code: "proposal_error", message: "entry has no proposal block: #{pending_key}" } } unless proposal
  
          target_key = proposal["target_key"]
          return { error: { code: "proposal_error", message: "proposal missing target_key" } } unless target_key
  
          target_env = ctx.read(target_key)
  
          body_diff = Textus::Protocol::Diff.body(target_env&.body, env.body)
          meta_diff = Textus::Protocol::Diff.meta(target_env&.meta&.dig("_meta") || {}, env.meta&.dig("_meta") || {})
  
          entry = ctx.manifest.data.entries.find { |e| e.key == target_key }
          target_schema = entry&.schema_ref
          proposal_schema = env&.meta&.dig("_meta", "schema")
          schema_diff = nil
          if proposal_schema && target_schema != proposal_schema
            schema_diff = Textus::Protocol::Diff.schema({ "schema" => target_schema }, { "schema" => proposal_schema })
          end
  
          result = { "pending_key" => pending_key, "target_key" => target_key }
          result["body"] = body_diff if body_diff
          result["meta"] = meta_diff if meta_diff
          result["schema"] = schema_diff if schema_diff
          result["summary"] = Textus::Protocol::Diff.summary(result)
          result
        end
      end
    end
  end
end
  