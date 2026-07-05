module Textus
  module Protocol
    class Manifest
      module Schema
        # The closed coordination vocabulary (ADR 0028; five in 0033; unified in
        # 0034; the quarantine + derived ZONE-KINDS folded into one `machine` kind
        # in ADR 0091). Each kind pairs with the capability that authorizes
        # originating bytes in it.
        LANES = {
          "canon" => "author",
          "workspace" => "keep",
          "machine" => "converge",
          "queue" => "propose",
          "raw" => "ingest",
        }.freeze

        LANE_KINDS         = LANES.keys.freeze
        CAPABILITIES       = LANES.values.uniq.freeze
        KIND_REQUIRES_VERB = LANES

        # Key whitelists and rule-field registry (ADR 0109).
        ROOT_KEYS  = %w[version roles owner lanes entries data audit worker].freeze
        LANE_KEYS  = %w[name kind owner desc].freeze
        ENTRY_KEYS = %w[key schema format naming tracked].freeze
        AUDIT_KEYS = %w[max_size keep].freeze

        OWNER_SUBJECT_PATTERN = /\A[a-z][a-z0-9_-]*\z/

        # Public entry point — structural validation then semantic checks.
        def self.validate!(raw) = Validator.validate!(raw)

        def self.walk(raw, allowed, path)
          raw.each_key do |k|
            raise BadManifest.new("unknown key '#{k}' at '#{path}'") unless allowed.include?(k)
          end
        end
      end
    end
  end
end
