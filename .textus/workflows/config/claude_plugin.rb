Textus.workflow "claude_plugin" do
  match "artifacts.claude-plugin"

  step :build do |_, ctx|
    project_env = Textus::Action::Get.new(key: "knowledge.project")
                    .call(container: ctx.container, call: ctx.call)
    project = project_env&.meta || {}
    repo    = project["repo"]
    command = { "type" => "command", "command" => "textus boot" }
    session_start = %w[startup clear compact].map { |m| { "matcher" => m, "hooks" => [command] } }

    { "content" => {
        "name"        => project["name"] || "textus",
        "description" => "Durable, multi-writer repo memory. " \
                         "Auto-orients each session with `textus boot`.",
        "version"     => Textus::VERSION,
        "homepage"    => repo,
        "repository"  => repo,
        "license"     => "MIT",
        "hooks"       => { "SessionStart" => session_start },
        "mcpServers"  => { "textus" => { "command" => "textus", "args" => %w[mcp serve] } },
      }
    }
  end

  publish
end
