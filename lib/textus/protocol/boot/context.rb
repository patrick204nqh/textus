require "json"

module Textus
  module Protocol
    module Boot
      # The boot response answers 5 questions for the agent:
      #   1. Where am I?       → contract (store_root, etag)
      #   2. What can I do?     → agent (verbs, writable lanes, propose lane, tips)
      #   3. What can't I do?   → plugin (protected_paths, protected_lanes, publish_targets)
      #   4. What's here?       → project (identity), state (loop, runbooks, entry_blueprints)
      #   5. How do I talk?     → agent.protocol (envelope_shape, roles, discipline)
      module Context
        def self.build(manifest:, event_store:, file_system:, layout:)
          etag       = Textus::Value::Etag.for_contract(layout)
          latest_seq = event_store.latest[:seq]
          context    = read_boot_context(manifest, file_system, layout)
          agent_role = manifest.policy.proposer_role

          lanes_list      = lanes_for(manifest)
          blueprints      = build_blueprints(manifest)
          project         = build_project(manifest, file_system)
          runbooks        = build_runbooks(manifest, file_system)
          loop_data       = build_loop(manifest, file_system)
          read_v, write_v = build_verb_lists(manifest, agent_role)
          writable        = build_writable_lanes(manifest, agent_role)
          propose_lane    = manifest.policy.propose_lane_for(agent_role)
          prot_lanes      = protected_lanes_for(manifest, agent_role)
          pub_targets     = publish_targets_from_sentinels(file_system, layout)
          prot_paths      = build_protected_paths(prot_lanes, pub_targets, layout)

          payload = {
            "protocol" => Textus::PROTOCOL,
            "contract" => {
              "etag" => etag,
              "store_root" => layout.root,
            },
            "project" => project,
            "state" => {
              "latest_seq" => latest_seq,
              "entry_blueprints" => blueprints,
              "runbooks" => runbooks,
              "loop" => loop_data,
            },
            "lanes" => lanes_list,
            "agent" => {
              "verbs" => { "read" => read_v, "write" => write_v },
              "writable_lanes" => writable,
              "propose_lane" => propose_lane,
              "protocol" => Protocol.build(manifest),
              "tips" => [
                { "when" => "write an entry", "then" => "`data` param: String for body, Hash for content" },
                { "when" => "edit a protected path", "then" => "`textus propose key=my-change data=...` — human reviews and accepts" },
                { "when" => "explore recent changes", "then" => "`textus pulse` then `textus get <changed_key>`" },
                { "when" => "find related entries", "then" => "`textus graph key=<key> depth=2`" },
              ],
            },
            "plugin" => {
              "protected_paths" => prot_paths,
              "protected_lanes" => prot_lanes,
              "publish_targets" => pub_targets,
            },
          }
          payload["context"] = context if context
          payload
        end

        # ── entry reading helpers ──

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

        def self.read_entry_meta(manifest, file_system, key)
          res = manifest.resolver.resolve(key)
          return nil unless res.path && file_system.exists?(res.path)

          mentry = res.entry
          raw = file_system.read(res.path)
          parsed = Textus::Protocol::Format.for(mentry.format).parse(raw, path: res.path)
          parsed["_meta"]
        rescue Textus::Error
          nil
        end

        def self.read_entry_body(manifest, file_system, key)
          res = manifest.resolver.resolve(key)
          return nil unless res.path && file_system.exists?(res.path)

          mentry = res.entry
          raw = file_system.read(res.path)
          parsed = Textus::Protocol::Format.for(mentry.format).parse(raw, path: res.path)
          parsed["body"].to_s
        rescue Textus::Error
          nil
        end

        def self.read_entry_family_meta(manifest, file_system, prefix)
          manifest.resolver.enumerate(prefix: prefix, include_keyless: true)
                  .reject { |row| row[:key] == prefix }
                  .sort_by { |row| row[:key] }
                  .filter_map { |row| read_entry_meta(manifest, file_system, row[:key]) }
        end

        # ── project / runbooks / loop ──

        def self.build_project(manifest, file_system)
          identity = read_entry_meta(manifest, file_system, "knowledge.loop.intent.0003-identity") || {}
          {
            "name" => identity["name"],
            "description" => identity["description"],
            "commands" => (identity["commands"] || {}).map { |k, v| "- **#{k}**: `#{v}`" }.join("\n"),
            "has_commands" => !(identity["commands"] || {}).empty?,
          }
        end

        def self.build_runbooks(manifest, file_system)
          read_entry_family_meta(manifest, file_system, "knowledge.loop.execution").filter_map do |meta|
            next unless meta

            row = { "name" => meta["name"], "description" => meta["description"] }
            row["schema"] = meta["role"] if meta["role"]
            row
          end
        end

        LOOP_NODES = %w[intent constraint.repo constraint.protocol judgment.engineering
                        judgment.agent-behavior evidence execution adoption].freeze

        def self.build_loop(manifest, file_system)
          body = read_entry_body(manifest, file_system, "knowledge.loop.judgment.agent-behavior.0001-loop-behavior")
          excerpt = body ? body.lines.first(5).join : ""
          { "nodes" => LOOP_NODES, "excerpt" => excerpt }
        end

        # ── blueprints ──

        META_GLOSSARY = {
          "knowledge.loop.adoption" => { "node" => "target loop node", "confidence" => "high|medium|low",
                                         "signal" => "observation type", "summary" => "brief description" },
          "scratchpad.proposals" => { "proposal" => "{ target_key, action }" },
          "raw" => { "source" => "{ kind, url, path, label }" },
        }.freeze

        def self.build_blueprints(manifest)
          manifest.data.entries.map do |entry|
            bp = { "key_prefix" => entry.key, "format" => entry.format.to_s, "naming" => entry.naming.to_s }
            bp["schema"] = entry.schema.to_s if entry.schema
            meta = META_GLOSSARY[entry.key]
            bp["meta"] = meta if meta
            bp
          end
        end

        # ── verb lists ──

        def self.build_verb_lists(manifest, agent_role)
          read_verbs = Textus::Protocol::VerbRegistry.registered.select { |s| s.read? && s.mcp? }.map { |s| s.verb.to_s }

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

          [read_verbs, write_verbs]
        end

        # ─── writable lanes ──

        def self.build_writable_lanes(manifest, agent_role)
          return [] unless agent_role

          manifest.data.declared_lane_kinds.keys.each_with_object([]) do |ln, acc|
            writers = manifest.policy.writers_for(ln)
            acc << ln if writers.include?(agent_role)
          end
        end

        # ── lanes ──

        def self.lanes_for(manifest)
          manifest.data.declared_lane_kinds.keys.map do |name|
            row = { "name" => name, "writers" => manifest.policy.writers_for(name) }
            purpose = manifest.data.lane_descs[name]
            row["purpose"] = purpose if purpose && !purpose.empty?
            row
          end
        end

        def self.protected_lanes_for(manifest, agent_role)
          return [] unless agent_role

          manifest.data.declared_lane_kinds.keys.reject do |name|
            manifest.policy.writers_for(name).include?(agent_role)
          end
        end

        # ── protected paths ──

        def self.build_protected_paths(protected_lanes, publish_targets, layout)
          repo_root = File.dirname(layout.root)
          data_paths = protected_lanes.map { |lane| layout.lane_path(lane) }
          abs_targets = publish_targets.map { |t| File.join(repo_root, t) }
          (data_paths + abs_targets).uniq.sort
        end

        def self.publish_targets_from_sentinels(file_system, layout)
          sentinel_root = File.join(layout.root, "track", "sentinels")
          return [] unless file_system.directory?(sentinel_root)

          file_system.glob(File.join(sentinel_root, "**", "*.textus-managed.json")).filter_map do |path|
            JSON.parse(file_system.read(path))["target"]
          rescue JSON::ParserError
            nil
          end.uniq.sort
        end

        class NullEntryIndex
          def record(...) = nil
          def remove(...) = nil
        end
      end
    end
  end
end
