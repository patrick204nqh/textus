Textus.workflow "opencode_config" do
  match "artifacts.config.opencode"

  step :build do |_, ctx|
    { "content" => {
      "$schema" => "https://opencode.ai/config.json",
      "mcp" => { "textus" => { "type" => "local", "command" => %w[bundle exec exe/textus mcp serve], "enabled" => true } },
      "instructions" => ["AGENTS.md"],
    } }
  end

  publish
end
