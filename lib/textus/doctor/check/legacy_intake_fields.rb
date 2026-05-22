require "yaml"

module Textus
  module Doctor
    class Check
      # Scans the raw manifest YAML for entry-level intake.ttl /
      # intake.on_stale / intake.sync_budget_ms keys. Manifest parsing
      # already raises on these in 0.9.2 — this check exists for the case
      # where doctor is run against a problem manifest separately (e.g. CI
      # lint or an exploration session that loads the YAML directly).
      class LegacyIntakeFields < Check
        LEGACY_KEYS = %w[ttl on_stale sync_budget_ms].freeze

        def call
          out = []
          path = File.join(store.root, "manifest.yaml")
          return out unless File.exist?(path)

          raw = safe_load(path)
          return out unless raw.is_a?(Hash)

          Array(raw["entries"]).each do |entry|
            next unless entry.is_a?(Hash)

            intake = entry["intake"]
            next unless intake.is_a?(Hash)

            offending = LEGACY_KEYS.select { |k| intake.key?(k) }
            next if offending.empty?

            out << issue_for(entry["key"], offending)
          end
          out
        end

        private

        def safe_load(path)
          YAML.load_file(path)
        rescue StandardError
          nil
        end

        def issue_for(key, fields)
          {
            "code" => "manifest.legacy_intake_fields",
            "level" => "error",
            "subject" => key.to_s,
            "message" => "entry '#{key}' carries legacy intake.#{fields.join(", intake.")} " \
                         "(removed in 0.9.2 — freshness lives in top-level policies:)",
            "fix" => "run `textus migrate policies` to hoist these into a policies: block",
          }
        end
      end
    end
  end
end
