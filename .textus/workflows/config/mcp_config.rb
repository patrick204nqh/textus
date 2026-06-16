Textus.workflow "mcp_config" do
  match "artifacts.mcp-config"

  step :build do |_, ctx|
    { "content" => {
      "mcpServers" => {
        "textus" => {
          "command" => "bundle",
          "args" => %w[exec exe/textus --root .textus mcp serve],
        },
      },
    } }
  end

  publish
end
