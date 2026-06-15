Textus.workflow "opencode_config" do
  match "artifacts.derived.opencode-config"

  step :derive do |data, ctx|
    {
      "$schema" => "https://opencode.ai/config.json",
      "lsp"     => {
        "ruby" => {
          "type"       => "local",
          "command"    => %w[bundle exec ruby-lsp],
          "enabled"    => true,
          "extensions" => [".rb", ".rake", ".gemspec", ".ru"],
        },
      },
      "mcp"     => {
        "textus" => { "type" => "local", "command" => %w[textus mcp serve], "enabled" => true },
      },
      "plugin"  => ["textus@git+https://github.com/patrick204nqh/textus.git"],
      "instructions" => ["AGENTS.md"],
    }
  end

  publish
end
