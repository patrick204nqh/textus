# Projects this repo's Claude Code plugin manifest (.claude-plugin/plugin.json)
# from canon + the gem version (ADR 0086): identity from knowledge.project,
# version from Textus::VERSION (so it can never drift), the SessionStart hook
# and the MCP server inline. Built as a derived artifact with provenance: false
# so the manifest carries no _meta block.
Textus.hook do |reg|
  reg.on(:transform_rows, :plugin_manifest_reducer) do |rows:, **|
    project = rows.find { |r| r["_key"] == "knowledge.project" } || {}
    repo = project["repo"]
    command = { "type" => "command", "command" => "textus boot --lean" }
    session_start = %w[startup clear compact].map do |m|
      { "matcher" => m, "hooks" => [command] }
    end
    {
      "name" => project["name"] || "textus",
      "description" => "Durable, multi-writer repo memory for humans, agents, and automation. " \
                       "Auto-orients each session with a lean `textus boot` so the agent starts " \
                       "knowing the store's zones, write authority, and contract etag.",
      "version" => Textus::VERSION,
      "homepage" => repo,
      "repository" => repo,
      "license" => "MIT",
      "hooks" => { "SessionStart" => session_start },
      "mcpServers" => { "textus" => { "command" => "textus", "args" => %w[mcp serve] } },
    }
  end
end
