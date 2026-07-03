module Textus
  module Proposal
    module Handlers
      module_function

      def propose(key:, container:, call:, meta: nil, body: nil, content: nil)
        zone = container.manifest.policy.propose_lane_for(call.role)
        return { error: { code: "propose_forbidden", message: "role '#{call.role}' has no writable propose_lane" } } unless zone

        full_key = "#{zone}.#{key}"
        mentry = container.manifest.resolver.resolve(full_key).entry
        env = container.writer.put(
          full_key, mentry:, call:,
                    payload: Textus::Value::Payload.new(meta: meta || {}, body:, content:)
        )
        env.to_h_for_wire
      end

      def accept(pending_key:, container:, call:, dry_run: false)
        env = container.reader.read(pending_key)
        proposal = env&.meta&.dig("proposal")
        return { error: { code: "proposal_error", message: "entry has no proposal block: #{pending_key}" } } unless proposal

        target = proposal["target_key"]
        return { error: { code: "proposal_error", message: "proposal missing target_key" } } unless target

        action = proposal["action"] || "put"

        if dry_run
          target_env = container.reader.read(target)
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
          mentry = container.manifest.resolver.resolve(target).entry
          container.writer.put(target, mentry:, call:,
                                       payload: Textus::Value::Payload.new(meta: env.meta["_meta"] || {}, body: env.body, content: nil))
        when "delete"
          container.writer.delete(target, call:)
        else
          return { error: { code: "proposal_error", message: "unknown action: #{action}" } }
        end

        container.writer.delete(pending_key, call:)
        { "protocol" => Textus::PROTOCOL, "accepted" => pending_key,
          "target_key" => target, "action" => action, "cascade_key" => target }
      end

      def reject(pending_key:, container:, call:, reason: nil)
        mentry = container.manifest.resolver.resolve(pending_key).entry
        unless mentry.in_proposal_lane?(container.manifest.policy)
          return { error: { code: "proposal_error", message: "reject: '#{pending_key}' is not in a proposal zone (zone=#{mentry.lane})" } }
        end

        env = container.reader.read(pending_key)
        proposal = env&.meta&.dig("proposal")
        return { error: { code: "proposal_error", message: "entry has no proposal block: #{pending_key}" } } unless proposal

        target_key = proposal["target_key"]
        container.writer.delete(pending_key, mentry:, call:)
        result = { "protocol" => Textus::PROTOCOL, "rejected" => pending_key, "target_key" => target_key }
        result["reason"] = reason if reason
        result
      end

      def diff(pending_key:, container:, call:)
        env = container.reader.read(pending_key)
        proposal = env&.meta&.dig("proposal")
        return { error: { code: "proposal_error", message: "entry has no proposal block: #{pending_key}" } } unless proposal

        target_key = proposal["target_key"]
        return { error: { code: "proposal_error", message: "proposal missing target_key" } } unless target_key

        target_env = container.reader.read(target_key)

        body_diff = Textus::Protocol::Diff.body(target_env&.body, env.body)
        meta_diff = Textus::Protocol::Diff.meta(target_env&.meta&.dig("_meta") || {}, env.meta&.dig("_meta") || {})

        entry = container.manifest.data.entries.find { |e| e.key == target_key }
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
