# rubocop:disable Metrics/BlockLength
Textus.workflow "opencode_config" do
  on "artifacts.config.opencode"

  step :build do |_, _ctx|
    { "content" => {
      "$schema" => "https://opencode.ai/config.json",
      "lsp" => {
        "yaml-ls" => {
          "command" => ["node_modules/.bin/yaml-language-server", "--stdio"],
          "extensions" => %w[yml yaml],
        },
        "json-ls" => {
          "command" => ["node_modules/.bin/vscode-json-languageserver", "--stdio"],
          "extensions" => ["json"],
        },
        "marksman" => {
          "command" => %w[marksman serve],
          "extensions" => ["md"],
        },
        "ruby-lsp" => {
          "command" => %w[bundle exec ruby-lsp],
          "extensions" => %w[rb erb builder rake ru],
        },
      },
      "mcp" => { "textus" => { "type" => "local", "command" => %w[bundle exec exe/textus mcp serve], "enabled" => true } },
      "instructions" => ["AGENTS.md"],
    } }
  end
  publish to: "opencode.json"
end
# rubocop:enable Metrics/BlockLength
