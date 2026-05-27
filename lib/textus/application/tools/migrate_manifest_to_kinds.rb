require "yaml"

module Textus
  module Application
    module Tools
      module MigrateManifestToKinds
        module_function

        def upgrade_yaml(yaml_text)
          raw = YAML.safe_load(yaml_text, aliases: false)
          raw["entries"] = Array(raw["entries"]).map { |row| upgrade_row(row) }
          YAML.dump(raw)
        end

        def upgrade_row(row)
          return row if row["kind"]

          row.merge("kind" => infer_kind(row))
        end

        def infer_kind(row)
          return "intake"  if row["intake"].is_a?(Hash) || row["intake_handler"]
          return "derived" if row["template"] || row["compute"] || row["generator"] || row["projection"]
          return "nested"  if row["nested"] == true

          "leaf"
        end
      end
    end
  end
end
