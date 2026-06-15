Textus.workflow "orientation" do
  match "artifacts.derived.orientation"

  step :derive do |data, ctx|
    project_env = Textus::Action::Get.new(key: "knowledge.project")
                    .call(container: ctx.container, call: ctx.call)
    project_row = (project_env&.meta || {}).merge("_key" => "knowledge.project")

    runbook_keys = Textus::Action::List.new(prefix: "knowledge.runbooks", lane: nil,
                                             role: ctx.call.role)
                     .call(container: ctx.container, call: ctx.call)
                     .fetch("entries", []).map { |e| e["key"] }
    runbook_rows = runbook_keys.map do |k|
      env = Textus::Action::Get.new(key: k).call(container: ctx.container, call: ctx.call)
      (env&.meta || {}).merge("_key" => k)
    end

    rows = [project_row] + runbook_rows
    p    = rows.find { |r| r["_key"] == "knowledge.project" } || {}
    rbs  = rows.select { |r| r["_key"]&.start_with?("knowledge.runbooks.") }

    {
      "project" => {
        "name"         => p["name"],
        "description"  => p["description"],
        "commands"     => (p["commands"] || {}).map { |k, v| "- **#{k}**: `#{v}`" }.join("\n"),
        "has_commands" => !p["commands"].nil? && !p["commands"].empty?,
      },
      "runbooks" => rbs.map { |r| { "name" => r["name"], "description" => r["description"] } },
    }
  end

  publish
end
