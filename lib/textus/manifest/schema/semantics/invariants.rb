module Textus
  class Manifest
    module Schema
      module Semantics
        module Invariants
          def check_invariants!(raw)
            check_roles!(raw["roles"])
            check_lanes!(raw["lanes"])
            check_entries!(raw["entries"])
            check_rules!(raw["rules"])
            check_single_queue!(raw)
            check_single_machine!(raw)
            walk(raw["audit"], AUDIT_KEYS, "$.audit") if raw["audit"].is_a?(Hash)
          end

          def check_roles!(roles)
            return if roles.nil?

            roles.each_with_index do |r, i|
              path = "$.roles[#{i}]"
              name = r["name"]
              unless Textus::Value::Role::NAMES.include?(name)
                raise BadManifest.new(
                  "unknown role name '#{name}' at '#{path}' (allowed: #{Textus::Value::Role::NAMES.join(", ")})",
                )
              end
              Array(r["can"]).each do |verb|
                next if CAPABILITIES.include?(verb)

                hint = %w[ingest fetch].include?(verb) ? " — the quarantine capability folded into 'converge' (ADR 0090)" : ""
                raise BadManifest.new(
                  "unknown capability '#{verb}' for role '#{name}' at '#{path}' " \
                  "(known: #{CAPABILITIES.join(", ")})#{hint}",
                )
              end
            end

            author_holders = roles.count { |r| Array(r["can"]).include?("author") }
            return if author_holders <= 1

            raise BadManifest.new(
              "manifest declares #{author_holders} roles with the author capability; at most one is allowed",
            )
          end

          def check_lanes!(lanes)
            Array(lanes).each_with_index do |z, i|
              walk(z, LANE_KEYS, "$.lanes[#{i}]")
              next unless %w[quarantine derived].include?(z["kind"])

              raise BadManifest.new(
                "lane kind '#{z["kind"]}' at '$.lanes[#{i}]' was folded into 'machine' (ADR 0091) — " \
                "use `kind: machine`",
              )
            end
          end

          def check_entries!(entries)
            Array(entries).each_with_index do |e, i|
              path = "$.entries[#{i}]"
              walk(e, ENTRY_KEYS, path)
              check_publish_block!(e, path)
              walk(e["source"], SOURCE_KEYS, "#{path}.source") if e.is_a?(Hash) && e["source"].is_a?(Hash)
            end
          end

          def check_rules!(rules)
            Array(rules).each_with_index do |r, i|
              path = "$.rules[#{i}]"
              walk(r, RULE_KEYS, path)
              FIELD_REGISTRY.each_value do |meta|
                next unless meta[:sub_keys]

                value = r.is_a?(Hash) ? r[meta[:yaml_key]] : nil
                walk(value, meta[:sub_keys], "#{path}.#{meta[:yaml_key]}") if value.is_a?(Hash)
              end
            end
          end

          def check_publish_block!(entry, path)
            return unless entry.is_a?(Hash) && entry.key?("publish")

            block = entry["publish"]
            if block.is_a?(Hash)
              raise BadManifest.new(
                "publish: at '#{path}.publish' must be a list of targets (ADR 0094); the map form was retired.",
              )
            end
            raise BadManifest.new("publish: must be a list of targets at '#{path}.publish'") unless block.is_a?(Array)

            block.each_with_index do |t, i|
              raise BadManifest.new("publish target ##{i} must be a mapping at '#{path}.publish'") unless t.is_a?(Hash)

              walk(t, %w[to tree template inject_boot], "#{path}.publish[#{i}]")
            end
          end

          def check_single_queue!(raw)
            queues = Array(raw["lanes"]).select { |z| z["kind"] == "queue" }.map { |z| z["name"] }
            return if queues.size <= 1

            raise BadManifest.new("at most one lane may declare kind: queue (found: #{queues.join(", ")})")
          end

          def check_single_machine!(raw)
            machines = Array(raw["lanes"]).select { |z| z["kind"] == "machine" }.map { |z| z["name"] }
            return if machines.size <= 1

            raise BadManifest.new("at most one lane may declare kind: machine (found: #{machines.join(", ")})")
          end

          def walk(hash, allowed, path)
            return unless hash.is_a?(Hash)

            hash.each_key do |k|
              next if allowed.include?(k)

              raise BadManifest.new("unknown key '#{k}' at '#{path}'")
            end
          end
        end
      end
    end
  end
end
