module Textus
  module Lanes
    module Scratchpad
      module Handlers
        PROPOSALS_PARENT_KEY = "scratchpad.proposals"

        module_function

        SESSION_PARENT_KEY = "scratchpad.sessions"

        def session_open(ctx:, call:)
          uuid = SecureRandom.uuid
          key = "scratchpad.sessions.#{uuid}.session"

          content = { "session_id" => uuid, "created_at" => Time.now.utc.iso8601, "status" => "active" }
          ctx.put(key:, meta: {}, body: JSON.generate(content), content: nil, call:)

          boot = Textus::Protocol::Boot.build(container: ctx.container) rescue nil
          result = { "session_id" => uuid, "status" => "active" }
          result["boot"] = boot if boot
          result
        end

        def parent_mentry(ctx)
          ctx.manifest.data.entries.find { |e| e.key == SESSION_PARENT_KEY }
        end

        def propose(key:, ctx:, call:, meta: nil, body: nil, content: nil)
          full_key = "#{PROPOSALS_PARENT_KEY}.#{key}"
          env = ctx.put(key: full_key, meta: meta || {}, body:, content:, call:)
          env.to_h_for_wire
        end

        def accept(pending_key:, ctx:, call:, dry_run: false)
          env = ctx.read(key: pending_key)
          proposal = env&.meta&.dig("proposal")
          raise Textus::ProposalError.new("entry has no proposal block: #{pending_key}") unless proposal

          target = proposal["target_key"]
          raise Textus::ProposalError.new("proposal missing target_key") unless target

          action = proposal["action"] || "put"

          if dry_run
            target_env = ctx.read(key: target)
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
            target_meta = env.meta.to_h.except("proposal")
            ctx.put(key: target, meta: target_meta, body: env.body, content: env.content, call:)
          when "delete"
            ctx.delete(key: target, call:)
          else
            raise Textus::ProposalError.new("unknown action: #{action}")
          end

          ctx.delete(key: pending_key, call:)
          { "protocol" => Textus::PROTOCOL, "accepted" => pending_key,
            "target_key" => target, "action" => action, "cascade_key" => target }
        end

        def reject(pending_key:, ctx:, call:, reason: nil)
          env = ctx.read(key: pending_key)
          proposal = env&.meta&.dig("proposal")
          raise Textus::ProposalError.new("entry has no proposal block: #{pending_key}") unless proposal

          target_key = proposal["target_key"]
          ctx.delete(key: pending_key, call:)
          result = { "protocol" => Textus::PROTOCOL, "rejected" => pending_key, "target_key" => target_key }
          result["reason"] = reason if reason
          result
        end

        def diff(pending_key:, ctx:, call:)
          env = ctx.read(key: pending_key)
          proposal = env&.meta&.dig("proposal")
          raise Textus::ProposalError.new("entry has no proposal block: #{pending_key}") unless proposal

          target_key = proposal["target_key"]
          raise Textus::ProposalError.new("proposal missing target_key") unless target_key

          target_env = ctx.read(key: target_key)

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

        def session_close(session_id:, ctx:, call:, nodes_checked: nil)
          key = "scratchpad.sessions.#{session_id}.session"
          env = ctx.read(key:)
          raise Textus::UsageError.new("session not found: #{session_id}") unless env

          current = JSON.parse(env.body || "{}")
          content = current.merge("status" => "sealed", "closed_at" => Time.now.utc.iso8601)
          ctx.put(key:, meta: {}, body: JSON.generate(content), content: nil, call:)

          feedback_key = "scratchpad.sessions.#{session_id}.feedback"
          duration = current["created_at"] ? "#{((Time.now.utc - Time.parse(current["created_at"])) / 60).round}m" : "unknown"
          feedback = {
            "node" => "feedback",
            "confidence" => "medium",
            "signal" => "session_closed",
            "summary" => "Session #{session_id[0..8]} sealed after #{duration}. " \
                         "Created at #{current["created_at"]}, closed at #{Time.now.utc.iso8601}.",
          }
          feedback["nodes_checked"] = nodes_checked if nodes_checked
          ctx.put(key: feedback_key, meta: {}, body: JSON.generate(feedback), content: nil, call:)

          { "session_id" => session_id, "status" => "sealed", "feedback_key" => feedback_key }
        end
      end
    end
  end
end
