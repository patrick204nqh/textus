# Reshapes the raw projection rows into the keys orientation.mustache
# references. Without this, the template would only see the flat rows list.
# Mirrors examples/project — textus dogfoods its own build/publish path.
Textus.hook do |reg|
  reg.on(:transform_rows, :orientation_reducer) do |rows:, **|
    project_row = rows.find { |r| r["_key"] == "knowledge.project" } || {}
    runbook_rows = rows.select { |r| r["_key"]&.start_with?("knowledge.runbooks.") }

    {
      "project" => {
        "name" => project_row["name"],
        "description" => project_row["description"],
      },
      "runbooks" => runbook_rows.map { |r| { "name" => r["name"], "description" => r["description"] } },
    }
  end
end
