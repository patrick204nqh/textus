# Reducer that reshapes the raw projection rows into the keys the
# orientation.mustache template references. Without this, the template
# would only have access to the flat rows list.
module Textus
  module Step
    class OrientationTransform < Transform
      def call(rows:, config:, **)
        project_row = rows.find { |r| r["_key"] == "knowledge.project" } || {}
        runbook_rows = rows.select { |r| r["_key"]&.start_with?("knowledge.runbooks.") }

        {
          "project" => {
            "name" => project_row["name"],
            "description" => project_row["description"]
          },
          "runbooks" => runbook_rows.map { |r| { "name" => r["name"], "description" => r["description"] } }
        }
      end
    end
  end
end
