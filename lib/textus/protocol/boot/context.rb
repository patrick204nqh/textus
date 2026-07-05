module Textus
  module Protocol
    module Boot
      module Context
        def self.build(manifest:, event_store:, file_system:, layout:)
          etag       = Textus::Value::Etag.for_contract(layout)
          latest_seq = event_store.latest[:seq]
          artifact   = read_artifact_content(manifest, file_system, layout)
          context    = read_boot_context(manifest, file_system, layout)

          stable = artifact || inline_boot_content(manifest, latest_seq)
          if stable["agent_quickstart"]
            stable = stable.merge(
              "agent_quickstart" => stable["agent_quickstart"].merge("latest_seq" => latest_seq),
            )
          end

          payload = {
            "protocol" => Textus::PROTOCOL,
            "store_root" => layout.root,
            "contract_etag" => etag,
          }.merge(stable)
          payload["context"] = context if context
          payload
        end

        def self.read_artifact_content(manifest, file_system, _layout)
          key = "artifacts.boot"
          res = manifest.resolver.resolve(key)
          return nil unless res.path && file_system.exists?(res.path)

          mentry = res.entry
          raw = file_system.read(res.path)
          parsed = Textus::Protocol::Format.for(mentry.format).parse(raw, path: res.path)
          parsed["content"]
        rescue Textus::Error
          nil
        end

        def self.read_boot_context(manifest, file_system, _layout)
          res = manifest.resolver.resolve("knowledge.boot")
          return nil unless res.path && file_system.exists?(res.path)

          mentry = res.entry
          raw = file_system.read(res.path)
          parsed = Textus::Protocol::Format.for(mentry.format).parse(raw, path: res.path)
          body = parsed["body"]&.strip
          body.nil? || body.empty? ? nil : body
        rescue Textus::Error
          nil
        end

        def self.inline_boot_content(manifest, _latest_seq)
          agent_role     = manifest.policy.proposer_role
          writable_lanes = manifest.data.declared_lane_kinds.keys.each_with_object([]) do |ln, acc|
            next unless agent_role

            writers = manifest.policy.writers_for(ln)
            acc << ln if writers.include?(agent_role)
          end

          author_writers = manifest.policy.writers_for("knowledge")
          agent_has_author = agent_role && author_writers.include?(agent_role)
          write_verbs = if agent_role
                          mcp_verbs = Textus::Protocol::VerbRegistry.registered.select { |s| s.write? && s.mcp? }
                          unless agent_has_author
                            forbidden = %i[accept reject].to_set.freeze
                            mcp_verbs = mcp_verbs.reject { |s| forbidden.include?(s.verb) }
                          end
                          mcp_verbs.map { |s| s.verb.to_s }
                        else
                          []
                        end

          meta_glossary = {
            "knowledge.loop.adoption" => { "node" => "target loop node", "confidence" => "high|medium|low",
                                           "signal" => "observation type", "summary" => "brief description" },
            "scratchpad.proposals" => { "proposal" => "{ target_key, action }" },
            "raw" => { "source" => "{ kind, url, path, label }" },
          }.freeze

          blueprints = manifest.data.entries.map do |entry|
            bp = { "key_prefix" => entry.key, "format" => entry.format.to_s, "naming" => entry.naming.to_s }
            bp["schema"] = entry.schema.to_s if entry.schema
            meta = meta_glossary[entry.key]
            bp["meta"] = meta if meta
            bp
          end

          {
            "lanes" => lanes_for(manifest),
            "entry_blueprints" => blueprints,
            "workflow_tips" => [
              { "when" => "write an entry", "then" => "`data` param: String for body, Hash for content" },
              { "when" => "edit a protected path", "then" => "`textus propose key=my-change data=...` — human reviews and accepts" },
              { "when" => "explore recent changes", "then" => "`textus pulse` then `textus get <changed_key>`" },
              { "when" => "find related entries", "then" => "`textus graph key=<key> depth=2`" },
            ],
            "agent_quickstart" => {
              "read_verbs" => Textus::Protocol::VerbRegistry.registered.select { |s| s.read? && s.mcp? }.map { |s| s.verb.to_s },
              "write_verbs" => write_verbs,
              "writable_lanes" => writable_lanes,
              "propose_lane" => manifest.policy.propose_lane_for(agent_role),
            },
          }
        end

        def self.lanes_for(manifest)
          manifest.data.declared_lane_kinds.keys.map do |name|
            row = { "name" => name, "writers" => manifest.policy.writers_for(name) }
            purpose = manifest.data.lane_descs[name]
            row["purpose"] = purpose if purpose && !purpose.empty?
            row
          end
        end

        class NullEntryIndex
          def record(...) = nil
          def remove(...) = nil
        end
      end
    end
  end
end
