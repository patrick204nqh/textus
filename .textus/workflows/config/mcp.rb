Textus.workflow "mcp_config" do
  match "artifacts.config.mcp"

  step :build do |_, _ctx|
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
