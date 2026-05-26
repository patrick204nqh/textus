# Reducer that reshapes the raw projection rows into the keys the
# orientation.mustache template references. Without this, the template
# would only have access to the flat rows list.
Textus.on(:transform_rows, :orientation_reducer) do |rows:, **|
  project_row = rows.find { |r| r["_key"] == "identity.project" } || {}
  runbook_rows = rows.select { |r| r["_key"]&.start_with?("working.runbooks.") }

  {
    "project" => {
      "name" => project_row["name"],
      "description" => project_row["description"]
    },
    "runbooks" => runbook_rows.map { |r| { "name" => r["name"], "description" => r["description"] } }
  }
end
