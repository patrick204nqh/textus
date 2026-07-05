module Textus
  module Protocol
    class Manifest
      module Schema
        # The manifest's key whitelists and the rule-field registry — the schema's
        # data tables (ADR 0109; the vocabulary lives in Schema::Vocabulary).
        module Keys
          ROOT_KEYS  = %w[version roles owner lanes entries data audit worker].freeze
          LANE_KEYS  = %w[name kind owner desc].freeze
          ENTRY_KEYS = %w[
            key schema format naming tracked
          ].freeze
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
end
