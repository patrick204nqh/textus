module Textus
  module Domain
    module Policy
      # The `upkeep:` rule field (ADR 0090, reshaped ADR 0091). NO `on:` tag —
      # the grammar is read from the keys present:
      #   { ttl, action, budget_ms } → age-based   (Lifecycle)
      #   { strategy }               → dependency   (Materialize)
      # Mixing the two key-sets, or an empty block, is a parse error. WHICH
      # grammar is legal for WHICH entry-kind is enforced once, at load, by
      # Schema.validate_upkeep_kinds! (it has the entry in hand; this class does
      # not). The action set is left wide here and narrowed per entry-kind by
      # that load validation.
      class Upkeep
        AGE_KEYS = %w[ttl action budget_ms].freeze
        DEP_KEYS = %w[strategy].freeze

        attr_reader :lifecycle, :materialize

        def initialize(raw)
          keys = raw.keys.map(&:to_s)
          age  = keys.intersect?(AGE_KEYS)
          dep  = keys.intersect?(DEP_KEYS)

          if age && dep
            raise Textus::BadManifest.new("upkeep cannot mix age (#{AGE_KEYS.join("/")}) and dependency (#{DEP_KEYS.join("/")}) keys")
          end
          raise Textus::BadManifest.new("upkeep must carry either #{AGE_KEYS.join("/")} or #{DEP_KEYS.join("/")}") unless age || dep

          if dep
            @materialize = Materialize.new(on_change: raw["strategy"])
            @lifecycle = nil
          else
            @lifecycle = Lifecycle.new(ttl: raw["ttl"], on_expire: raw["action"], budget_ms: raw["budget_ms"])
            @materialize = nil
          end
        end

        def stale?         = !@lifecycle.nil?
        def source_change? = !@materialize.nil?
      end
    end
  end
end
