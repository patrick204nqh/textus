module Textus
  class Manifest
    # The manifest schema. Its data is split across Schema::Vocabulary (the
    # coordination vocabulary) and Schema::Keys (key whitelists + FIELD_REGISTRY)
    # as of ADR 0109; the validation walk lives in Schema::Validator (ADR 0107).
    # The constants are re-exported here so callers keep saying `Schema::LANES`.
    module Schema
      # Re-export the vocabulary.
      LANES              = Vocabulary::LANES
      LANE_KINDS         = Vocabulary::LANE_KINDS
      CAPABILITIES       = Vocabulary::CAPABILITIES
      KIND_REQUIRES_VERB = Vocabulary::KIND_REQUIRES_VERB
      # Re-export the keys + registry.
      ROOT_KEYS             = Keys::ROOT_KEYS
      ROLE_KEYS             = Keys::ROLE_KEYS
      LANE_KEYS             = Keys::LANE_KEYS
      ENTRY_KEYS            = Keys::ENTRY_KEYS
      PUBLISH_KEYS          = Keys::PUBLISH_KEYS
      SOURCE_KEYS           = Keys::SOURCE_KEYS
      RETENTION_KEYS        = Keys::RETENTION_KEYS
      AUDIT_KEYS            = Keys::AUDIT_KEYS
      FIELD_REGISTRY        = Keys::FIELD_REGISTRY
      RULE_KEYS             = Keys::RULE_KEYS
      OWNER_SUBJECT_PATTERN = Keys::OWNER_SUBJECT_PATTERN

      # Public entry points — the validation walk lives in Schema::Validator
      # (ADR 0107). Kept here so callers keep speaking to `Schema`.
      def self.validate!(raw) = Validator.validate!(raw)

      def self.validate_source_and_retention!(manifest) = Validator.validate_source_and_retention!(manifest)
    end
  end
end
