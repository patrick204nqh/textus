module Textus
  class Manifest
    class Policy
      # Garbage collection (ADR 0093). A glob-matched rule slot: when an entry
      # ages past `ttl`, retire it. Destructive only — runs on the full
      # `converge` pass, never on a write (ADR 0079's invariant). Orthogonal to
      # production (`source:`): an intake entry can re-pull hourly AND archive
      # after 90 days. `warn`/`refresh` are gone (refresh is implied by an
      # intake source; warn never fired after ADR 0089's pure-read get).
      class Retention
        ACTIONS = %i[drop archive].freeze

        attr_reader :action

        def initialize(raw)
          @ttl = raw["ttl"] or
            raise Textus::BadManifest.new("retention requires a 'ttl:'")
          @action = (raw["action"] || "").to_s.to_sym
          return if ACTIONS.include?(@action)

          raise Textus::BadManifest.new("retention action must be one of #{ACTIONS.join("|")}, got #{raw["action"].inspect}")
        end

        def ttl_seconds = Textus::Value::Duration.seconds(@ttl)
        def destructive? = true
      end
    end
  end
end
