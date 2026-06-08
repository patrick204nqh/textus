module Textus
  class Manifest
    module Schema
      # The manifest validation walk. Extracted from Schema (ADR 0107) so the
      # schema module is its data — the coordination vocabulary (LANES + derived)
      # and the key whitelists / FIELD_REGISTRY — while the validation *logic*
      # lives here. Lexically nested under Schema, so bare constant references
      # (ROOT_KEYS, LANES, FIELD_REGISTRY, …) resolve to Schema's constants.
      module Validator
        module_function

        def validate!(raw)
          raise BadManifest.new("manifest must be a hash") unless raw.is_a?(Hash)

          walk(raw, ROOT_KEYS, "$")
          validate_roles!(raw["roles"])
          validate_zones!(raw["zones"])
          validate_entries!(raw["entries"])
          validate_owners!(raw["zones"], raw["entries"])
          validate_rules!(raw["rules"])
          walk(raw["audit"], AUDIT_KEYS, "$.audit") if raw["audit"].is_a?(Hash)
          validate_single_queue!(raw)
          validate_single_machine!(raw)
          validate_zone_kind_consistency!(raw)
        end

        def validate_zones!(zones)
          Array(zones).each_with_index do |z, i|
            walk(z, ZONE_KEYS, "$.zones[#{i}]")
            if z["kind"].nil?
              raise BadManifest.new("zone '#{z["name"]}' at '$.zones[#{i}]' must declare a kind (one of: #{ZONE_KINDS.join(", ")})")
            end
            next if ZONE_KINDS.include?(z["kind"])

            if %w[quarantine derived].include?(z["kind"])
              raise BadManifest.new(
                "zone kind '#{z["kind"]}' at '$.zones[#{i}]' was folded into 'machine' (ADR 0091) — " \
                "use `kind: machine`",
              )
            end

            raise BadManifest.new(
              "unknown zone kind '#{z["kind"]}' at '$.zones[#{i}]' (known: #{ZONE_KINDS.join(", ")})",
            )
          end
        end

        def validate_entries!(entries)
          Array(entries).each_with_index do |e, i|
            path = "$.entries[#{i}]"
            reject_retired_publish_keys!(e, path)
            reject_retired_render_keys!(e, path)
            walk(e, ENTRY_KEYS, path)
            validate_publish_block!(e, path)
            walk(e["source"], SOURCE_KEYS, "#{path}.source") if e["source"]
          end
        end

        # Retired keys are no longer allowed, so `walk` would reject them as merely
        # "unknown"; intercept first with the migration path so a pre-0.43 manifest
        # gets a useful error. `publish_each` was removed (ADR 0051); `publish_to`/
        # `publish_tree` were folded into the `publish:` block (ADR 0052);
        # `index_filename` was removed (ADR 0053).
        def reject_retired_publish_keys!(entry, path)
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
            "index_filename was removed in 0.43.0 (ADR 0053) at '#{path}' — a nested entry now enumerates " \
            "each file as a key; to mirror a directory of files to a consumer path use `publish: { tree: \"...\" }`.",
          )
        end

        # ADR 0094: rendering is a publish concern. An entry no longer
        # declares a build-time template or render flags — they move onto publish
        # targets. Provenance lives in the data's `_meta`, not a flag.
        def reject_retired_render_keys!(entry, path)
          return unless entry.is_a?(Hash)

          if entry.key?("template")
            raise BadManifest.new(
              "entry-level `template:` was removed at '#{path}' (ADR 0094): rendering is a " \
              "publish concern — `publish: [{ to:, template: }]`.",
            )
          end
          if entry.key?("inject_boot")
            raise BadManifest.new(
              "entry-level `inject_boot:` was removed at '#{path}' (ADR 0094): it is a render " \
              "flag — `publish: [{ to:, inject_boot: }]`.",
            )
          end
          return unless entry.key?("provenance")

          raise BadManifest.new("entry-level `provenance:` was removed at '#{path}' (ADR 0094): provenance lives in the data's `_meta`.")
        end

        # ADR 0094: publish is a LIST of target objects. The old
        # `{ to: [...] }` / `{ tree: … }` map forms are retired (fold hint).
        def validate_publish_block!(entry, path)
          return unless entry.is_a?(Hash) && entry.key?("publish")

          block = entry["publish"]
          if block.is_a?(Hash)
            raise BadManifest.new(
              "publish: at '#{path}.publish' must be a list of targets " \
              "[{ to:, template:? } | { tree: }] (ADR 0094); the map form was retired.",
            )
          end
          raise BadManifest.new("publish: must be a list of targets at '#{path}.publish'") unless block.is_a?(Array)

          block.each_with_index do |t, i|
            raise BadManifest.new("publish target ##{i} must be a mapping at '#{path}.publish'") unless t.is_a?(Hash)

            walk(t, %w[to tree template inject_boot], "#{path}.publish[#{i}]")
          end
        end

        def validate_rules!(rules)
          Array(rules).each_with_index do |r, i|
            path = "$.rules[#{i}]"
            reject_retired_rule_keys!(r, path)
            if r.is_a?(Hash) && r.key?("upkeep")
              raise BadManifest.new(
                "rule key `upkeep:` was removed (ADR 0093): move age-GC to `retention:` " \
                "and production (handler/template) to the entry's `source:`",
              )
            end
            walk(r, RULE_KEYS, path)
            FIELD_REGISTRY.each_value do |meta|
              next unless meta[:sub_keys]

              value = r[meta[:yaml_key]]
              walk(value, meta[:sub_keys], "#{path}.#{meta[:yaml_key]}") if value.is_a?(Hash)
            end
          end
        end

        # ADR 0093 split production from age-GC: age-GC moved to the `retention:`
        # rule; intake cadence + production (handler/template) moved to the
        # entry's `source:` block. Legacy `lifecycle:`/`materialize:` rule keys
        # are rejected with a migration hint toward the new shape.
        def reject_retired_rule_keys!(rule, path)
          return unless rule.is_a?(Hash)

          hints = {
            "lifecycle" => "age GC moved to the `retention:` rule ({ ttl, action: drop|archive }); " \
                           "intake cadence to the entry's `source: { ttl }`",
            "materialize" => "moved to the entry's `source: { on_write: sync|async }`",
          }
          hints.each do |old, hint|
            next unless rule.key?(old)

            raise BadManifest.new("`#{old}:` was removed at '#{path}' (ADR 0093) — #{hint}.")
          end
        end

        def validate_roles!(roles)
          return if roles.nil?
          raise BadManifest.new("roles: must be a list") unless roles.is_a?(Array)

          roles.each_with_index do |r, i|
            path = "$.roles[#{i}]"
            walk(r, ROLE_KEYS, path)
            name = r["name"] or raise BadManifest.new("role at '#{path}' missing name")
            unless Textus::Role::NAMES.include?(name)
              raise BadManifest.new(
                "unknown role name '#{name}' at '#{path}' " \
                "(allowed: #{Textus::Role::NAMES.join(", ")})",
              )
            end
            Array(r["can"]).each do |verb|
              next if CAPABILITIES.include?(verb)

              # The quarantine capability folded into reconcile (ADR 0090); a
              # manifest still naming the old quarantine capability (`ingest`, or
              # legacy `fetch`) gets a pointed hint rather than a bare error.
              hint = %w[ingest fetch].include?(verb) ? " — the quarantine capability folded into 'reconcile' (ADR 0090)" : ""
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

        # Owners are validated against the SAME closed archetype set as role names
        # (ADR 0045 D1) so attribution can't bypass the closed-name guarantee.
        # Applies to both zone owners and entry owners; owner is optional, so a
        # nil owner is not an error.
        def validate_owners!(zones, entries)
          Array(zones).each_with_index do |z, i|
            check_owner!(z["owner"], "$.zones[#{i}]")
          end
          Array(entries).each_with_index do |e, i|
            check_owner!(e["owner"], "$.entries[#{i}]")
          end
        end

        def check_owner!(owner, path)
          return if owner.nil?
          return if valid_owner?(owner)

          raise BadManifest.new(
            "invalid owner '#{owner}' at '#{path}' " \
            "(expected <archetype> or <archetype>:<subject>, " \
            "archetype one of: #{Textus::Role::NAMES.join(", ")})",
          )
        end

        # The owner-validation rule: an `owner:` token is either a bare archetype
        # (`agent`) or `<archetype>:<subject>` (`human:patrick`). The archetype is
        # gated against the closed Role::NAMES set (so attribution can't smuggle in
        # a name the role side rejects, ADR 0045 D1); the subject is the free-form
        # principal, validated by OWNER_SUBJECT_PATTERN. Split on the FIRST ':'
        # only — a subject may not itself contain ':' (the pattern excludes it), so
        # `human:a:b` is rejected.
        def valid_owner?(token)
          return false unless token.is_a?(String) && !token.empty?

          archetype, subject = token.split(":", 2)
          return false unless Textus::Role::NAMES.include?(archetype)
          return true if subject.nil?

          OWNER_SUBJECT_PATTERN.match?(subject)
        end

        def walk(hash, allowed, path)
          return unless hash.is_a?(Hash)

          hash.each_key do |k|
            next if allowed.include?(k)

            raise BadManifest.new("unknown key '#{k}' at '#{path}'")
          end
        end

        def validate_single_queue!(raw)
          queues = Array(raw["zones"]).select { |z| z["kind"] == "queue" }.map { |z| z["name"] }
          return if queues.size <= 1

          raise BadManifest.new(
            "at most one zone may declare kind: queue (found: #{queues.join(", ")})",
          )
        end

        def validate_single_machine!(raw)
          machines = Array(raw["zones"]).select { |z| z["kind"] == "machine" }.map { |z| z["name"] }
          return if machines.size <= 1

          raise BadManifest.new(
            "at most one zone may declare kind: machine (found: #{machines.join(", ")})",
          )
        end

        # ADR 0093: retention (drop/archive) is age-based GC; it is invalid on a
        # derived entry (a derived entry regenerates from its source, it isn't aged
        # out). Per ADR 0095 the produce-method is read from source.from on the one
        # Produced kind, so there is no longer a kind to agree against the source.
        # (Replaces validate_upkeep_kinds!.)
        def validate_source_and_retention!(manifest)
          manifest.data.entries.each do |entry|
            retention = manifest.rules.for(entry.key).retention
            next if retention.nil?
            next unless entry.derived?

            raise BadManifest.new(
              "entry '#{entry.key}': a derived entry regenerates from its source; " \
              "retention (drop/archive) is invalid",
            )
          end
        end

        # Write authority is derived from capabilities (ADR 0030): a zone of a
        # given kind can only be written by a role that holds the kind's required
        # verb. Reject a manifest declaring a zone whose required verb is held by
        # no role. Capabilities.resolve returns the defaults when `roles:` is nil,
        # so the capability union is all four verbs and every kind is satisfied.
        def validate_zone_kind_consistency!(raw)
          held = Capabilities.resolve(raw["roles"]).values.flatten.uniq

          Array(raw["zones"]).each_with_index do |z, i|
            verb = KIND_REQUIRES_VERB[z["kind"]]
            next if verb.nil? || held.include?(verb)

            raise BadManifest.new(
              "zone '#{z["name"]}' (#{z["kind"]}) at '$.zones[#{i}]' " \
              "needs a role with capability '#{verb}'; none declared",
            )
          end
        end
      end
    end
  end
end
