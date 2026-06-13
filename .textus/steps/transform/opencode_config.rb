# Projects this repo's opencode configuration (opencode.json)
# from canon (ADR 0086 mirror): registers the textus MCP server
# and includes AGENTS.md in the instructions.

module Textus
  module Step
    CONFIG = {
      "$schema" => "https://opencode.ai/config.json",
      "lsp" => {
        "ruby" => {
          "type" => "local",
          "command" => %w[bundle
                          exec
                          ruby-lsp], # or %w[bundle exec rubocop --lsp]
          "enabled" => true,
          "extensions" => [".rb", ".rake", ".gemspec", ".ru"],
        },
      },
      "mcp" => {
        "textus" => {
          "type" => "local",
          "command" => %w[textus mcp serve],
          "enabled" => true,
        },
      },
      "plugin" => [
        "textus@git+https://github.com/patrick204nqh/textus.git",
      ],
      "instructions" => ["AGENTS.md"],
    }

    class OpencodeConfigTransform < Transform
      def call(rows:, config:, **)
        _ = rows
        _ = config
        CONFIG
      end
    end
  end
end
