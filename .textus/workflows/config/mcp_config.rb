Textus.workflow "mcp_config" do
  match "artifacts.mcp-config"

  step :derive do |data, ctx|
    {
      "mcpServers" => {
        "textus" => {
          "command" => "bundle",
          "args"    => ["exec", "exe/textus", "--root", ".textus", "mcp", "serve"],
        },
      },
    }
  end

  publish
end
