require "zeitwerk"
require_relative "textus/version"
require_relative "textus/errors"
require_relative "textus/surfaces/mcp"
require_relative "textus/surfaces/mcp/errors"

loader = Zeitwerk::Loader.for_gem
loader.inflector.inflect(
  "cli" => "CLI",
  "json" => "Json",
  "yaml" => "Yaml",
  "io" => "IO",
  "mcp" => "MCP",
  "mcp_serve" => "MCPServe",
)
loader.ignore(File.expand_path("textus/errors.rb", __dir__))
loader.ignore(File.expand_path("textus/surfaces/mcp.rb", __dir__))
loader.ignore(File.expand_path("textus/surfaces/mcp/errors.rb", __dir__))
# Scaffold sources copied verbatim into user stores by `textus init`. They are
# templates for user-owned step classes, not gem constants — Zeitwerk must not
# manage or eager-load them.
loader.ignore(File.expand_path("textus/init/templates", __dir__))
loader.setup
loader.eager_load

# Derive CLI_VERBS after eager_load so all contract-declaring files are present
# (boot.rb loads first alphabetically; Dispatcher contracts are declared later).
Textus::Boot::CLI_VERBS = Textus::Boot.build_cli_verbs.freeze

module Textus
end
