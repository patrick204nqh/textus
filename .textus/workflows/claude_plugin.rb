Textus.workflow "claude_plugin" do
  match "artifacts.derived.claude-plugin"

  step :derive do |data, ctx|
    project_env = Textus::Action::Get.new(key: "knowledge.project")
                    .call(container: ctx.container, call: ctx.call)
    project     = project_env&.meta || {}
    repo        = project["repo"]
    command     = { "type" => "command", "command" => "textus boot --lean" }
    session_start = %w[startup clear compact].map { |m| { "matcher" => m, "hooks" => [command] } }

    {
      "name"        => project["name"] || "textus",
      "description" => "Durable, multi-writer repo memory for humans, agents, and automation. " \
                       "Auto-orients each session with a lean `textus boot` so the agent starts " \
                       "knowing the store's lanes, write authority, and contract etag.",
      "version"     => Textus::VERSION,
      "homepage"    => repo,
      "repository"  => repo,
      "license"     => "MIT",
      "hooks"       => { "SessionStart" => session_start },
      "mcpServers"  => { "textus" => { "command" => "textus", "args" => %w[mcp serve] } },
    }
  end

  publish
end
