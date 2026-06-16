Textus.workflow "mcp_config" do
  match "artifacts.mcp-config"

  step :build do |_, ctx|
    { "content" => {
        "mcpServers" => {
          "textus" => {
            "command" => "textus",
            "args"    => %w[--root .textus mcp serve],
          },
        },
      }
    }
  end

  publish
end
