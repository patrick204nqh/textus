module Textus
  class Manifest
    module Schema
      # The manifest's key whitelists and the rule-field registry — the schema's
      # data tables (ADR 0109; the vocabulary lives in Schema::Vocabulary).
      module Keys
        ROOT_KEYS  = %w[version roles lanes entries rules audit].freeze
        ROLE_KEYS  = %w[name can].freeze
        LANE_KEYS  = %w[name kind owner desc].freeze
        ENTRY_KEYS = %w[
          key path lane kind schema owner nested format
          source publish tracked ignore
        ].freeze
        # ADR 0052: the typed publish block — `publish: { to: [...] }` (file
        # fan-out) xor `publish: { tree: "dir" }` (subtree mirror).
        PUBLISH_KEYS = %w[to tree].freeze
        # entry-level external-generator block — only `from: external` is valid.
        # `from: fetch` and `from: derive` and their specific fields (handler,
        # config, ttl, select, pluck, sort_by, transform) were removed in the
        # workflow redesign.
        SOURCE_KEYS = %w[from command sources].freeze
        # ADR 0093: rule-level GC slot. drop/archive only (refresh gone).
        RETENTION_KEYS = %w[ttl action].freeze

        # The ONE source of truth for the rule-block field set (WS3). Adding a
        # rule field means adding one entry here; everything downstream derives
        # from it so the ~9 enumeration sites the audit found can't drift:
        #   - Schema::RULE_KEYS and the per-field sub-key walk (Schema::Validator)
        #   - Rules: the RuleSet members, EMPTY_SET, the `for` slots accumulator,
        #     Block's attr_readers, and the parse dispatch
        #   - Doctor::Check::RuleAmbiguity SLOTS (in_ambiguity)
        #   - Read::RuleList / Read::RuleExplain field membership
        #     (in_rule_list / in_rule_explain)
        #
        # Per field:
        #   yaml_key     manifest key used in a rule block
        #   policy_class the Manifest::Policy backing the field (nil = raw value)
        #   validation   :immediate (instantiate the policy at parse, surfacing
        #                shape errors eagerly), :deferred (shape-check + carry
        #                the raw Hash; guard predicates validate at Dispatch::Auth
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
          guard: {
            yaml_key: "guard",
            policy_class: nil,
            validation: :deferred, sub_keys: nil, arg_key: nil,
            in_pick: true, in_ambiguity: true,
            in_rule_list: true, in_rule_explain: %i[lean detail]
          },
          retention: {
            yaml_key: "retention",
            policy_class: Textus::Manifest::Policy::Retention,
            validation: :tagged, sub_keys: RETENTION_KEYS, arg_key: nil,
            in_pick: true, in_ambiguity: true,
            in_rule_list: true, in_rule_explain: %i[lean detail]
          },
          react: {
            yaml_key: "react",
            policy_class: Textus::Manifest::Policy::React,
            validation: :immediate, sub_keys: nil, arg_key: :raw,
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
      end
    end
  end
end
