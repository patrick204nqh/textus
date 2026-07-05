# Consolidates 4 config-generation workflows (contributing, mcp, opencode, plugin).
# Reads project identity from knowledge; builds all configs from shared data.
Textus.workflow "config" do
  on "knowledge.loop.**", "artifacts.config"
  priority 2

  step :build do |_, ctx|
    project_env = ctx.read("knowledge.loop.intent.0003-identity")
    project = project_env&.meta || {}
    repo = project["repo"]

    boot_hook = { "type" => "command", "command" => "textus boot" }
    session_start = %w[startup clear compact].map { |m| { "matcher" => m, "hooks" => [boot_hook] } }

    cbm_cache_dir = File.join(ctx.repo_root, ".cache", "codebase-memory")
    cbm_env = { "CBM_CACHE_DIR" => cbm_cache_dir }

    { "content" => {
      "project_name" => project["name"].to_s,
      "mcpServers" => {
        "textus" => {
          "command" => "bundle", "args" => %w[exec exe/textus --root .textus mcp serve],
        },
        "codebase-memory" => {
          "command" => "codebase-memory-mcp", "args" => [], "env" => cbm_env,
        },
        "codegraph" => {
          "command" => "codegraph", "args" => %w[serve --mcp],
        },
      },
      "lsp" => {
        "yaml-ls" => { "command" => %w[node_modules/.bin/yaml-language-server --stdio], "extensions" => %w[yml yaml] },
        "json-ls" => { "command" => %w[node_modules/.bin/vscode-json-languageserver --stdio], "extensions" => ["json"] },
        "marksman" => { "command" => %w[marksman serve], "extensions" => ["md"] },
        "ruby-lsp" => { "command" => %w[bundle exec ruby-lsp], "extensions" => %w[rb erb builder rake ru] },
      },
      "mcp" => {
        "textus" => { "type" => "local", "command" => %w[bundle exec exe/textus mcp serve], "enabled" => true },
        "codebase-memory" => { "type" => "local", "command" => ["codebase-memory-mcp"], "env" => cbm_env, "enabled" => true },
        "codegraph" => { "type" => "local", "command" => %w[codegraph serve --mcp], "enabled" => true },
      },
      "permission" => {
        "edit" => {
          "*" => "allow",
          ".textus/data/knowledge/**" => "deny",
          ".textus/data/artifacts/**" => "deny",
          "docs/**" => "deny",
          "README.md" => "deny",
          "CONTRIBUTING.md" => "deny",
          "SECURITY.md" => "deny",
          "CLAUDE.md" => "deny",
          "AGENTS.md" => "deny",
          "CHANGELOG.md" => "deny",
          "CODE_OF_CONDUCT.md" => "deny",
          ".mcp.json" => "deny",
        },
      },
      "instructions" => ["AGENTS.md"],
      "name" => project["name"] || "textus",
      "description" => "Durable, multi-writer repo memory. Auto-orients each session with `textus boot`.",
      "version" => Textus::VERSION,
      "homepage" => repo,
      "repository" => repo,
      "license" => "MIT",
      "hooks" => { "SessionStart" => session_start },
    } }
  end

  save to: "artifacts.config"
  publish to: "CONTRIBUTING.md", template: "docs/meta/contributing.erb"
  publish to: ".mcp.json", template: "config/mcp.json.erb"
  publish to: "opencode.json", template: "config/opencode.json.erb"
  publish to: ".claude-plugin/plugin.json", template: "config/plugin.json.erb"
end
