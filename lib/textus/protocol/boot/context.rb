module Textus
  module Protocol
    module Boot
      module Context
        def self.build(manifest:, audit_log:, file_system:, layout:)
          etag       = Textus::Value::Etag.for_contract(layout.root)
          latest_seq = audit_log.latest_seq
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

        def self.read_artifact_content(manifest, file_system, layout)
          key = "artifacts.boot"
          res = manifest.resolver.resolve(key)
          return nil unless res.path && file_system.exists?(res.path)

          entry_store = Textus::Store::EntryStore.new(
            file_system:, manifest:, audit_log: nil, layout:, entry_index: NullEntryIndex.new,
          )
          env = entry_store.read(key)
          env&.content
        rescue Textus::Error
          nil
        end

        def self.read_boot_context(manifest, file_system, layout)
          res = manifest.resolver.resolve("knowledge.boot")
          return nil unless res.path && file_system.exists?(res.path)

          entry_store = Textus::Store::EntryStore.new(
            file_system:, manifest:, audit_log: nil, layout:, entry_index: NullEntryIndex.new,
          )
          env = entry_store.read("knowledge.boot")
          body = env&.body&.strip
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

          {
            "lanes" => lanes_for(manifest),
            "agent_quickstart" => {
              "read_verbs" => Textus::Protocol::VerbRegistry.registered.select { |s| s.read? && s.mcp? }.map { |s| s.verb.to_s },
              "write_verbs" => agent_role ? Textus::Protocol::VerbRegistry.registered.select { |s| s.write? && s.mcp? }.map { |s| s.verb.to_s } : [],
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
