module Textus
  class Manifest
    module Schema
      ROOT_KEYS    = %w[version roles zones entries rules audit].freeze
      ROLE_KEYS    = %w[name can].freeze
      ZONE_KEYS    = %w[name kind owner desc].freeze
      # The closed coordination vocabulary (ADR 0028; completed at five in ADR
      # 0033; unified in ADR 0034; the quarantine capability folded into
      # reconcile in ADR 0090). Each lane pairs a zone-kind with the capability
      # that authorizes originating bytes in it. This table is the ONE source of
      # truth; the derived constants below cannot drift. It is a FUNCTION, not a
      # bijection — `quarantine` and `derived` are both machine-maintained lanes
      # and share `reconcile` (ADR 0090). Key order is canon-first so the
      # unknown-kind error message reads canon, workspace, quarantine, queue,
      # derived.
      LANES = {
        "canon" => "author",
        "workspace" => "keep",
        "quarantine" => "reconcile",
        "queue" => "propose",
        "derived" => "reconcile",
      }.freeze

      ZONE_KINDS         = LANES.keys.freeze
      CAPABILITIES       = LANES.values.uniq.freeze
      KIND_REQUIRES_VERB = LANES
      ENTRY_KEYS = %w[
        key path zone kind schema owner nested format
        compute template publish
        intake events inject_boot provenance ignore tracked
      ].freeze
      # ADR 0052: the typed publish block — `publish: { to: [...] }` (file
      # fan-out) xor `publish: { tree: "dir" }` (subtree mirror).
      PUBLISH_KEYS = %w[to tree].freeze
      COMPUTE_KEYS = %w[kind select pluck sort_by limit transform command sources].freeze
      INTAKE_KEYS  = %w[handler config].freeze
      # The UNION of keys across upkeep's tags; the generic sub-key walk enforces
      # only this set. The per-tag narrowing (rejecting cross-tag fields) lives in
      # Domain::Policy::Upkeep#reject_foreign! — UPKEEP_KEYS is not the complete
      # validation.
      UPKEEP_KEYS = %w[on ttl action budget_ms strategy].freeze

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
        upkeep: {
          yaml_key: "upkeep",
          policy_class: Textus::Domain::Policy::Upkeep,
          validation: :tagged, sub_keys: UPKEEP_KEYS, arg_key: nil,
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
        validate_zone_kind_consistency!(raw)
      end

      def self.validate_zones!(zones)
        Array(zones).each_with_index do |z, i|
          walk(z, ZONE_KEYS, "$.zones[#{i}]")
          if z["kind"].nil?
            raise BadManifest.new("zone '#{z["name"]}' at '$.zones[#{i}]' must declare a kind (one of: #{ZONE_KINDS.join(", ")})")
          end
          next if ZONE_KINDS.include?(z["kind"])

          raise BadManifest.new(
            "unknown zone kind '#{z["kind"]}' at '$.zones[#{i}]' (known: #{ZONE_KINDS.join(", ")})",
          )
        end
      end

      def self.validate_entries!(entries)
        Array(entries).each_with_index do |e, i|
          path = "$.entries[#{i}]"
          reject_retired_publish_keys!(e, path)
          walk(e, ENTRY_KEYS, path)
          validate_publish_block!(e, path)
          walk(e["compute"], COMPUTE_KEYS, "#{path}.compute") if e["compute"].is_a?(Hash)
          walk(e["intake"], INTAKE_KEYS, "#{path}.intake") if e["intake"].is_a?(Hash)
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

      # Shape of the ADR 0052 publish block: a Hash whose only keys are to/tree.
      # Exclusivity (both set) and per-mode rules stay in Publish.resolve (ADR 0049).
      def self.validate_publish_block!(entry, path)
        return unless entry.is_a?(Hash) && entry.key?("publish")

        block = entry["publish"]
        raise BadManifest.new("publish: must be a mapping with `to:` or `tree:` at '#{path}.publish'") unless block.is_a?(Hash)

        walk(block, PUBLISH_KEYS, "#{path}.publish")
      end

      def self.validate_rules!(rules)
        Array(rules).each_with_index do |r, i|
          path = "$.rules[#{i}]"
          reject_retired_rule_keys!(r, path)
          reject_unquoted_on!(r, path)
          walk(r, RULE_KEYS, path)
          FIELD_REGISTRY.each_value do |meta|
            next unless meta[:sub_keys]

            value = r[meta[:yaml_key]]
            walk(value, meta[:sub_keys], "#{path}.#{meta[:yaml_key]}") if value.is_a?(Hash)
          end
        end
      end

      # ADR 0090 merged the lifecycle/materialize rule fields into `upkeep`.
      def self.reject_retired_rule_keys!(rule, path)
        return unless rule.is_a?(Hash)

        %w[lifecycle materialize].each do |old|
          next unless rule.key?(old)

          tag = old == "lifecycle" ? "\"on\": stale" : "\"on\": source_change"
          raise BadManifest.new(
            "`#{old}:` was merged into `upkeep` at '#{path}' (ADR 0090) — use " \
            "`upkeep: { #{tag}, … }`.",
          )
        end
      end

      # `on:` is upkeep's discriminator, but a BARE `on:` parses as the YAML 1.1
      # boolean true (Psych), so `upkeep: { on: stale }` arrives as
      # `{ true => "stale" }`. Without this the generic sub-key walk rejects it
      # as a cryptic "unknown key 'true'"; intercept with a quoting hint instead.
      def self.reject_unquoted_on!(rule, path)
        return unless rule.is_a?(Hash)

        upkeep = rule["upkeep"]
        return unless upkeep.is_a?(Hash)
        return unless upkeep.keys.any? { |k| [true, false].include?(k) }

        raise BadManifest.new(
          "upkeep: the `on:` discriminator must be quoted in YAML at '#{path}.upkeep' — " \
          "a bare `on:` parses as the boolean true (YAML 1.1). " \
          "Write `upkeep: { \"on\": stale, … }` (ADR 0090).",
        )
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
