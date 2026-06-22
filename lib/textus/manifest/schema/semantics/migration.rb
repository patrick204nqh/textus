module Textus
  class Manifest
    module Schema
      module Semantics
        module Migration
          def check_migration!(raw)
            Array(raw["entries"]).each_with_index do |e, i|
              path = "$.entries[#{i}]"
              check_retired_publish_keys!(e, path)
              check_retired_render_keys!(e, path)
            end
            check_rules_retired_keys!(raw["rules"])
          end

          def check_retired_publish_keys!(entry, path)
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
              "index_filename was removed in 0.43.0 (ADR 0053) at '#{path}'.",
            )
          end

          def check_retired_render_keys!(entry, path)
            return unless entry.is_a?(Hash)

            if entry.key?("template")
              raise BadManifest.new(
                "entry-level `template:` was removed at '#{path}' (ADR 0094): rendering is a " \
                "publish concern — `publish: [{ to:, template: }]`.",
              )
            end
            if entry.key?("inject_boot")
              raise BadManifest.new(
                "entry-level `inject_boot:` was removed at '#{path}' (ADR 0094).",
              )
            end
            return unless entry.key?("provenance")

            raise BadManifest.new("entry-level `provenance:` was removed at '#{path}' (ADR 0094).")
          end

          def check_rules_retired_keys!(rules)
            Array(rules).each_with_index do |r, i|
              path = "$.rules[#{i}]"
              { "lifecycle" => "age GC moved to `retention:` rule", "materialize" => "removed (ADR 0093)" }
                .each do |old, hint|
                  next unless r.is_a?(Hash) && r.key?(old)

                  raise BadManifest.new("`#{old}:` was removed at '#{path}' (ADR 0093) — #{hint}.")
                end
              next unless r.is_a?(Hash) && r.key?("upkeep")

              raise BadManifest.new(
                "rule key `upkeep:` was removed (ADR 0093): move age-GC to `retention:` " \
                "and production to the entry's `source:`",
              )
            end
          end
        end
      end
    end
  end
end
