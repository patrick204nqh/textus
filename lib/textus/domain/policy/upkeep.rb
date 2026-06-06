module Textus
  module Domain
    module Policy
      # The unified `upkeep:` rule field (ADR 0090) — a tagged union discriminated
      # by `on:`. It routes to the existing inner policy and exposes it as a
      # sub-view, so reconcile/reactive call sites read `.lifecycle` / `.materialize`
      # unchanged:
      #   on: stale         → age-based, the Lifecycle grammar (ttl, action, budget_ms)
      #   on: source_change → dependency-based, the Materialize grammar (strategy)
      # The two grammars and bases stay distinct (ADR 0079/0087 substance preserved);
      # `ttl` never touches the dependency branch. A given key needs at most one
      # tag (doctor enforces it, see Check::UpkeepKindMismatch).
      class Upkeep
        TAGS               = %w[stale source_change].freeze
        STALE_KEYS         = %w[on ttl action budget_ms].freeze
        SOURCE_CHANGE_KEYS = %w[on strategy].freeze

        attr_reader :on, :lifecycle, :materialize

        def initialize(raw)
          @on = raw["on"].to_s
          case @on
          when "stale"
            reject_foreign!(raw, STALE_KEYS)
            @lifecycle   = Lifecycle.new(ttl: raw["ttl"], on_expire: raw["action"], budget_ms: raw["budget_ms"])
            @materialize = nil
          when "source_change"
            reject_foreign!(raw, SOURCE_CHANGE_KEYS)
            @materialize = Materialize.new(on_change: raw["strategy"])
            @lifecycle   = nil
          else
            raise Textus::BadManifest.new(
              "upkeep.on must be one of #{TAGS.join("|")}, got #{@on.inspect}",
            )
          end
        end

        def stale?         = @on == "stale"
        def source_change? = @on == "source_change"

        private

        def reject_foreign!(raw, allowed)
          extra = raw.keys.map(&:to_s) - allowed
          return if extra.empty?

          raise Textus::BadManifest.new(
            "upkeep on: #{@on} does not allow #{extra.join(", ")} (allowed: #{allowed.join(", ")})",
          )
        end
      end
    end
  end
end
