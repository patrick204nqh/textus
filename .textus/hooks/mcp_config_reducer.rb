# Projects this repo's .mcp.json (the dogfood MCP-server wiring) from a build
# projection. The content is static — the working-tree launch command — so the
# reducer ignores its rows and returns the server config (ADR 0086).
Textus.hook do |reg|
  reg.on(:transform_rows, :mcp_config_reducer) do |**|
    {
      "mcpServers" => {
        "textus" => {
          "command" => "bundle",
          "args" => ["exec", "exe/textus", "--root", ".textus", "mcp", "serve"],
        },
      },
    }
  end
end
