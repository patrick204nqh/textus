module Textus
  class Manifest
    module Schema # rubocop:disable Metrics/ModuleLength
      ROOT_KEYS    = %w[version roles zones entries rules audit].freeze
      ROLE_KEYS    = %w[name can].freeze
      ZONE_KEYS    = %w[name kind owner desc].freeze
      # The closed coordination vocabulary (ADR 0028; five in 0033; unified in
      # 0034; the quarantine + derived ZONE-KINDS folded into one `machine` kind
      # in ADR 0091). Each kind pairs with the capability that authorizes
      # originating bytes in it. ONE source of truth; the derived constants below
      # cannot drift. A BIJECTION again (0090 had two kinds → reconcile; 0091
      # collapses them, so kind ↔ capability is 1:1).
      LANES = {
        "canon" => "author",
        "workspace" => "keep",
        "machine" => "reconcile",
        "queue" => "propose",
      }.freeze

      ZONE_KINDS         = LANES.keys.freeze
      CAPABILITIES       = LANES.values.uniq.freeze
      KIND_REQUIRES_VERB = LANES
      ENTRY_KEYS = %w[
        key path zone kind schema owner nested format
        source publish
        events ignore tracked
      ].freeze
      # ADR 0052: the typed publish block — `publish: { to: [...] }` (file
      # fan-out) xor `publish: { tree: "dir" }` (subtree mirror).
      PUBLISH_KEYS = %w[to tree].freeze
      # ADR 0093/0094: entry-level acquisition block. `from: project` sources
      # expose flat projection fields (select/pluck/sort_by/transform) directly
      # on the source block (ADR 0094). Render fields (template/inject_boot/
      # provenance) that were formerly on the source are retired — they live on
      # publish targets. The legacy `project:` free hash and `template`/
      # `inject_boot`/`provenance` fields are kept here so the schema walk can
      # still emit the migration hint rather than a bare "unknown key".
      SOURCE_KEYS = %w[
        from handler config template project command sources ttl on_write inject_boot provenance
        select pluck sort_by transform
      ].freeze
      # ADR 0093: rule-level GC slot. drop/archive only (refresh gone).
      RETENTION_KEYS = %w[ttl action].freeze

      # The ONE source of truth for the rule-block field set (WS3). Adding a
      # rule field means adding one entry here; everything downstream derives
      # from it so the ~9 enumeration sites the audit found can't drift:
      #   - Schema::RULE_KEYS and the per-field sub-key walk (this file)
      #   - Rules: the RuleSet members, EMPTY_SET, the `for` slots accumulator,
      #     Block's attr_readers, and the parse dispatch
      #   - Doctor::Check::RuleAmbiguity SLOTS (in_ambiguity)
      #   - Read::RuleList / Read::RuleExplain field membership
      #     (in_rule_list / in_rule_explain)
      #
      # Per field:
      #   yaml_key     manifest key (handler_allowlist's intake_ prefix
      #                disambiguates from entry-level intake:, ADR 0059)
      #   policy_class the Domain::Policy backing the field (nil = raw value)
      #   validation   :immediate (instantiate the policy at parse, surfacing
      #                shape errors eagerly), :deferred (shape-check + carry
      #                the raw Hash; guard predicates validate at GuardFactory
      #                build time, ADR 0031), or :tagged (pass the raw Hash to a
      #                tagged-union policy that dispatches on its discriminator
      #                field, e.g. upkeep's on:)
      #   sub_keys     allowed nested keys for a mapping field (drives both the
      #                schema sub-key walk and the kwargs splat into policy_class)
      #   arg_key      for an immediate non-mapping field, the single kwarg the
      #                raw value is passed under
      #   in_pick      participates in the most-specific `for(key)` resolution
      #   in_ambiguity linted by doctor's same-specificity tie check
      #   in_rule_list shown in the whole-manifest rule_list view
      #   in_rule_explain depths the field shows at: :lean and/or :detail
      #
      # Key order here fixes the order of RULE_KEYS (after match), the slots,
      # the RuleSet members, and the doctor SLOTS.
      FIELD_REGISTRY = {
        handler_allowlist: {
          yaml_key: "intake_handler_allowlist",
          policy_class: Textus::Domain::Policy::HandlerAllowlist,
          validation: :immediate, sub_keys: nil, arg_key: :handlers,
          in_pick: true, in_ambiguity: true,
          in_rule_list: true, in_rule_explain: %i[detail]
        },
        guard: {
          yaml_key: "guard",
          policy_class: nil,
          validation: :deferred, sub_keys: nil, arg_key: nil,
          in_pick: true, in_ambiguity: true,
          in_rule_list: true, in_rule_explain: %i[lean detail]
        },
        retention: {
          yaml_key: "retention",
          policy_class: Textus::Domain::Policy::Retention,
          validation: :tagged, sub_keys: RETENTION_KEYS, arg_key: nil,
          in_pick: true, in_ambiguity: true,
          in_rule_list: true, in_rule_explain: %i[lean detail]
        },
      }.freeze

      RULE_KEYS = (["match"] + FIELD_REGISTRY.values.map { |m| m[:yaml_key] }).freeze
      AUDIT_KEYS = %w[max_size keep].freeze

      # Syntactic shape of an `owner:` subject token (the `patrick` in
      # `human:patrick`) — the subject half of the owner-validation rule below.
      # Role supplies the archetype set (Role::NAMES); this pattern is the
      # owner-specific part, so it lives with the rule that composes them
      # (ADR 0045 D1). Acting-role *names* are gated by Role::NAMES, not a regex.
      OWNER_SUBJECT_PATTERN = /\A[a-z][a-z0-9_-]*\z/

      def self.validate!(raw)
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

      def self.validate_zones!(zones)
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

      def self.validate_entries!(entries)
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
      def self.reject_retired_publish_keys!(entry, path)
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
      def self.reject_retired_render_keys!(entry, path)
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
      def self.validate_publish_block!(entry, path)
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

      def self.validate_rules!(rules)
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
      def self.reject_retired_rule_keys!(rule, path)
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

      def self.validate_roles!(roles)
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
      def self.validate_owners!(zones, entries)
        Array(zones).each_with_index do |z, i|
          check_owner!(z["owner"], "$.zones[#{i}]")
        end
        Array(entries).each_with_index do |e, i|
          check_owner!(e["owner"], "$.entries[#{i}]")
        end
      end

      def self.check_owner!(owner, path)
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
      def self.valid_owner?(token)
        return false unless token.is_a?(String) && !token.empty?

        archetype, subject = token.split(":", 2)
        return false unless Textus::Role::NAMES.include?(archetype)
        return true if subject.nil?

        OWNER_SUBJECT_PATTERN.match?(subject)
      end

      def self.walk(hash, allowed, path)
        return unless hash.is_a?(Hash)

        hash.each_key do |k|
          next if allowed.include?(k)

          raise BadManifest.new("unknown key '#{k}' at '#{path}'")
        end
      end

      def self.validate_single_queue!(raw)
        queues = Array(raw["zones"]).select { |z| z["kind"] == "queue" }.map { |z| z["name"] }
        return if queues.size <= 1

        raise BadManifest.new(
          "at most one zone may declare kind: queue (found: #{queues.join(", ")})",
        )
      end

      def self.validate_single_machine!(raw)
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
      def self.validate_source_and_retention!(manifest)
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
      def self.validate_zone_kind_consistency!(raw)
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
