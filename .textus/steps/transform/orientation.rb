# Reshapes the raw projection rows into the keys orientation.mustache
# references. Without this, the template would only see the flat rows list.
# Mirrors examples/project — textus dogfoods its own build/publish path.
module Textus
  module Step
    class OrientationTransform < Transform
      def call(rows:, config:, **)
        _ = config
        project_row = rows.find { |r| r["_key"] == "knowledge.project" } || {}
        runbook_rows = rows.select { |r| r["_key"]&.start_with?("knowledge.runbooks.") }

        {
          "project" => {
            "name" => project_row["name"],
            "description" => project_row["description"],
            "commands" => (project_row["commands"] || {}).map { |k, v| "- **#{k}**: `#{v}`" }.join("\n"),
            "has_commands" => !project_row["commands"].nil? && !project_row["commands"].empty?,
          },
          "runbooks" => runbook_rows.map { |r| { "name" => r["name"], "description" => r["description"] } },
        }
      end
    end
  end
end
