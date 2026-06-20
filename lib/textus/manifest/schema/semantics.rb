# frozen_string_literal: true

module Textus
  class Manifest
    module Schema
      # Cross-field rules and ADR migration hints. Called by Validator.validate!
      # AFTER the structural dry-schema Contract passes. Operates on the raw hash.
      module Semantics
        module_function

        def check!(raw)
          check_roles!(raw["roles"])
          check_lanes!(raw["lanes"])
          check_entries!(raw["entries"])
          check_owners!(raw["lanes"], raw["entries"])
          check_rules!(raw["rules"])
          check_single_queue!(raw)
          check_single_machine!(raw)
          check_lane_kind_consistency!(raw)
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
            check_retired_publish_keys!(e, path)
            check_retired_render_keys!(e, path)
            walk(e, ENTRY_KEYS, path)
            check_publish_block!(e, path)
            walk(e["source"], SOURCE_KEYS, "#{path}.source") if e.is_a?(Hash) && e["source"].is_a?(Hash)
          end
        end

        def check_retired_publish_keys!(entry, path)
          return unless entry.is_a?(Hash)

          if entry.key?("publish_each")
            raise BadManifest.new(
              "publish_each was removed in 0.42.0 (ADR 0051) at '#{path}' — " \
              "mirror the subtree with `publish: { tree: \"...\" }`.",
            )
          end
          if entry.key?("publish_to")
            raise BadManifest.new(
              "publish_to was replaced by the publish: block in 0.43.0 (ADR 0052) at '#{path}' — " \
              "use `publish: { to: [...] }`.",
            )
          end
          if entry.key?("publish_tree")
            raise BadManifest.new(
              "publish_tree was replaced by the publish: block in 0.43.0 (ADR 0052) at '#{path}' — " \
              "use `publish: { tree: \"...\" }`.",
            )
          end
          return unless entry.key?("index_filename")

          raise BadManifest.new(
            "index_filename was removed in 0.43.0 (ADR 0053) at '#{path}'.",
          )
        end

        def check_retired_render_keys!(entry, path)
          return unless entry.is_a?(Hash)

          if entry.key?("template")
            raise BadManifest.new(
              "entry-level `template:` was removed at '#{path}' (ADR 0094): rendering is a " \
              "publish concern — `publish: [{ to:, template: }]`.",
            )
          end
          if entry.key?("inject_boot")
            raise BadManifest.new(
              "entry-level `inject_boot:` was removed at '#{path}' (ADR 0094).",
            )
          end
          return unless entry.key?("provenance")

          raise BadManifest.new("entry-level `provenance:` was removed at '#{path}' (ADR 0094).")
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

        def check_owners!(lanes, entries)
          Array(lanes).each_with_index { |z, i| check_owner!(z["owner"], "$.lanes[#{i}]") }
          Array(entries).each_with_index { |e, i| check_owner!(e["owner"], "$.entries[#{i}]") }
        end

        def check_owner!(owner, path)
          return if owner.nil?
          return if valid_owner?(owner)

          raise BadManifest.new(
            "invalid owner '#{owner}' at '#{path}' " \
            "(expected <archetype> or <archetype>:<subject>, archetype one of: #{Textus::Value::Role::NAMES.join(", ")})",
          )
        end

        def valid_owner?(token)
          return false unless token.is_a?(String) && !token.empty?

          archetype, subject = token.split(":", 2)
          return false unless Textus::Value::Role::NAMES.include?(archetype)
          return true if subject.nil?

          OWNER_SUBJECT_PATTERN.match?(subject)
        end

        def check_rules!(rules)
          Array(rules).each_with_index do |r, i|
            path = "$.rules[#{i}]"
            # Check retired keys BEFORE the generic walk so specific hints fire first.
            { "lifecycle" => "age GC moved to `retention:` rule", "materialize" => "removed (ADR 0093)" }
              .each do |old, hint|
                next unless r.is_a?(Hash) && r.key?(old)

                raise BadManifest.new("`#{old}:` was removed at '#{path}' (ADR 0093) — #{hint}.")
              end
            if r.is_a?(Hash) && r.key?("upkeep")
              raise BadManifest.new(
                "rule key `upkeep:` was removed (ADR 0093): move age-GC to `retention:` " \
                "and production to the entry's `source:`",
              )
            end
            walk(r, RULE_KEYS, path)
            FIELD_REGISTRY.each_value do |meta|
              next unless meta[:sub_keys]

              value = r.is_a?(Hash) ? r[meta[:yaml_key]] : nil
              walk(value, meta[:sub_keys], "#{path}.#{meta[:yaml_key]}") if value.is_a?(Hash)
            end
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

        def check_lane_kind_consistency!(raw)
          held = Capabilities.resolve(raw["roles"]).values.flatten.uniq

          Array(raw["lanes"]).each_with_index do |z, i|
            verb = KIND_REQUIRES_VERB[z["kind"]]
            next if verb.nil? || held.include?(verb)

            raise BadManifest.new(
              "lane '#{z["name"]}' (#{z["kind"]}) at '$.lanes[#{i}]' " \
              "needs a role with capability '#{verb}'; none declared",
            )
          end
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
