module Textus
  module Lanes
    module Scratchpad
      module Handlers
        PROPOSALS_PARENT_KEY = "scratchpad.proposals"

        module_function

        SESSION_PARENT_KEY = "scratchpad.sessions"

        def session_open(ctx:, call:)
          today = Time.now.utc.strftime("%Y-%m-%d")
          slug = "#{('a'..'z').to_a.sample}#{SecureRandom.hex(4)}"
          session_id = "#{today}-#{slug}"
          key = "scratchpad.sessions.#{session_id}"

          content = { "session_id" => session_id, "created_at" => Time.now.utc.iso8601, "status" => "active" }
          ctx.put(key:, meta: {}, body: JSON.generate(content), content: nil, call:)

          boot = begin
            Textus::Protocol::Boot.build(container: ctx.container)
          rescue StandardError
            nil
          end
          result = { "session_id" => session_id, "status" => "active" }
          result["boot"] = boot if boot
          result
        end

        def parent_mentry(ctx)
          ctx.manifest.data.entries.find { |e| e.key == SESSION_PARENT_KEY }
        end

        def propose(key:, ctx:, call:, meta: nil, data: nil)
          body, content = data.is_a?(Hash) ? [nil, data] : [data, nil]

          if (target_key = meta&.dig("proposal", "target_key"))
            errors = Textus::Protocol::Blueprint::Controller.validate_naming(
              target_key, schemas: ctx.schemas, manifest: ctx.manifest
            )
            unless errors.empty?
              raise Textus::UsageError.new(errors.join("; "))
            end
          end

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

            # Parse body frontmatter to extract schema-relevant meta fields
            resolution = ctx.manifest.resolver.resolve(target)
            if env.body && !env.body.empty?
              parsed = Textus::Protocol::Format.for(resolution.entry.format).parse(env.body)
              body_meta = parsed["_meta"] || {}
              target_meta = body_meta.merge(target_meta)
            end

            # Re-validate constraints at promotion time
            payload = Textus::Value::Payload.new(meta: target_meta, body: env.body, content: env.content)
            errors = Textus::Protocol::Blueprint::Controller.validate(
              target, payload, schemas: ctx.schemas, manifest: ctx.manifest
            )
            unless errors.empty?
              raise Textus::UsageError.new(errors.join("; "))
            end

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
          key = "scratchpad.sessions.#{session_id}"
          env = ctx.read(key:)
          raise Textus::UsageError.new("session not found: #{session_id}") unless env

          current = JSON.parse(env.body || "{}")
          duration = current["created_at"] ? "#{((Time.now.utc - Time.parse(current["created_at"])) / 60).round}m" : "unknown"
          feedback = {
            "node" => "feedback",
            "confidence" => "medium",
            "signal" => "session_closed",
            "summary" => "Session #{session_id[0..8]} sealed after #{duration}. " \
                         "Created at #{current["created_at"]}, closed at #{Time.now.utc.iso8601}.",
          }
          feedback["nodes_checked"] = nodes_checked if nodes_checked

          content = current.merge("status" => "sealed", "closed_at" => Time.now.utc.iso8601, "feedback" => feedback)
          ctx.put(key:, meta: {}, body: JSON.generate(content), content: nil, call:)

          { "session_id" => session_id, "status" => "sealed", "feedback" => feedback }
        end
      end
    end
  end
end
