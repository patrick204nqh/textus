Textus.workflow "orientation" do
  match "artifacts.config.orientation"

  step :build do |_, ctx|
    project_env = Textus::Action::Get.new(key: "knowledge.project")
                    .call(container: ctx.container, call: ctx.call)
    project = project_env&.meta || {}

    runbook_keys = ctx.container.manifest.resolver
                      .enumerate(prefix: "knowledge.runbooks")
                      .map { |row| row[:key] }

    runbooks = runbook_keys.map do |k|
      env = Textus::Action::Get.new(key: k).call(container: ctx.container, call: ctx.call)
      env&.meta || {}
    end

    {
      "content" => {
        "project"  => {
          "name"         => project["name"],
          "description"  => project["description"],
          "commands"     => (project["commands"] || {}).map { |k, v| "- **#{k}**: `#{v}`" }.join("\n"),
          "has_commands" => !(project["commands"] || {}).empty?,
        },
        "runbooks" => runbooks.map { |r| { "name" => r["name"], "description" => r["description"] } },
      }
    }
  end

  publish
end
