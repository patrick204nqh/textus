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
          mentry = parent_mentry(ctx)

          base = File.join(ctx.layout.lane_path("scratchpad"), "sessions", uuid)
          %w[scripts notes output].each { |d| FileUtils.mkdir_p(File.join(base, d)) }

          content = { "session_id" => uuid, "created_at" => Time.now.utc.iso8601, "status" => "active" }
          ctx.write(key, mentry:, payload: ctx.payload(body: JSON.generate(content)), call:)

          { "session_id" => uuid, "status" => "active", "workspace" => base }
        end

        def parent_mentry(ctx)
          ctx.manifest.data.entries.find { |e| e.key == SESSION_PARENT_KEY }
        end

        def propose(key:, ctx:, call:, meta: nil, body: nil, content: nil)
          full_key = "#{PROPOSALS_PARENT_KEY}.#{key}"
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
          raise Textus::ProposalError.new("entry has no proposal block: #{pending_key}") unless proposal

          target = proposal["target_key"]
          raise Textus::ProposalError.new("proposal missing target_key") unless target

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
            raise Textus::ProposalError.new("unknown action: #{action}")
          end

          ctx.delete(pending_key, call:)
          { "protocol" => Textus::PROTOCOL, "accepted" => pending_key,
            "target_key" => target, "action" => action, "cascade_key" => target }
        end

        def reject(pending_key:, ctx:, call:, reason: nil)
          env = ctx.read(pending_key)
          proposal = env&.meta&.dig("proposal")
          raise Textus::ProposalError.new("entry has no proposal block: #{pending_key}") unless proposal

          target_key = proposal["target_key"]
          ctx.delete(pending_key, call:)
          result = { "protocol" => Textus::PROTOCOL, "rejected" => pending_key, "target_key" => target_key }
          result["reason"] = reason if reason
          result
        end

        def diff(pending_key:, ctx:, call:)
          env = ctx.read(pending_key)
          proposal = env&.meta&.dig("proposal")
          raise Textus::ProposalError.new("entry has no proposal block: #{pending_key}") unless proposal

          target_key = proposal["target_key"]
          raise Textus::ProposalError.new("proposal missing target_key") unless target_key

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

        def session_close(session_id:, ctx:, call:)
          key = "scratchpad.sessions.#{session_id}.session"
          env = ctx.read(key)
          raise Textus::UsageError.new("session not found: #{session_id}") unless env

          mentry = parent_mentry(ctx)
          current = JSON.parse(env.body || "{}")
          content = current.merge("status" => "sealed", "closed_at" => Time.now.utc.iso8601)
          ctx.write(key, mentry:, payload: ctx.payload(body: JSON.generate(content)), call:)

          feedback_key = "scratchpad.sessions.#{session_id}.feedback"
          duration = current["created_at"] ? "#{((Time.now.utc - Time.parse(current["created_at"])) / 60).round}m" : "unknown"
          feedback = {
            "node" => "feedback",
            "confidence" => "medium",
            "signal" => "session_closed",
            "summary" => "Session #{session_id[0..8]} sealed after #{duration}. " \
                         "Created at #{current["created_at"]}, closed at #{Time.now.utc.iso8601}.",
          }
          ctx.write(feedback_key, mentry:, payload: ctx.payload(body: JSON.generate(feedback)), call:)

          { "session_id" => session_id, "status" => "sealed", "feedback_key" => feedback_key }
        end
      end
    end
  end
end
