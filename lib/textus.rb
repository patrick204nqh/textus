require "zeitwerk"
require_relative "textus/version"
require_relative "textus/errors"

# Declare the MCP namespace before Zeitwerk encounters surface/mcp/errors.rb,
# which is pre-required below because its filename (errors.rb) does not match
# its constant name (ToolError) and cannot be managed by Zeitwerk.
module Textus
  module Surface
    module MCP
    end
  end
end

require_relative "textus/surface/mcp/errors"

loader = Zeitwerk::Loader.for_gem
loader.inflector.inflect(
  "cli" => "CLI",
  "json" => "Json",
  "yaml" => "Yaml",
  "mcp" => "MCP",
  "mcp_serve" => "MCPServe",
  "dsl" => "DSL",
)
loader.ignore(File.expand_path("textus/errors.rb", __dir__))
loader.ignore(File.expand_path("textus/surface/mcp/errors.rb", __dir__))
loader.ignore(File.expand_path("textus/init/templates", __dir__))
loader.setup
loader.eager_load

Textus::Boot::CLI_VERBS = Textus::Boot.build_cli_verbs.freeze
