# Projects this repo's opencode configuration (opencode.json)
# from canon (ADR 0086 mirror): registers the textus MCP server
# and includes AGENTS.md in the instructions.

CONFIG = {
  "$schema": "https://opencode.ai/config.json",
  lsp: {
    ruby: {
      type: "local",
      command: %w[bundle
                  exec
                  ruby-lsp], # or %w[bundle exec rubocop --lsp]
      enabled: true,
      extensions: [".rb", ".rake", ".gemspec", ".ru"],
    },
  },
  mcp: {
    textus: {
      type: "local",
      command: %w[textus mcp serve],
      enabled: true,
    },
  },
  plugin: [
    "superpowers@git+https://github.com/obra/superpowers.git",
    "superpowers-ruby@git+https://github.com/lucianghinda/superpowers-ruby.git",
    "ecc-universal@git+https://github.com/affaan-m/ECC.git",
    "textus@git+https://github.com/patrick204nqh/textus.git",
  ],
  instructions: ["AGENTS.md"],
}

Textus.hook do |reg|
  reg.on(:transform_rows, :opencode_config_reducer) do |rows:, **|
    rows.find { |r| r["_key"] == "knowledge.project" } || {}
    CONFIG
  end
end
