require "zeitwerk"
require_relative "textus/version"
require_relative "textus/errors"

require "sinatra/base"

loader = Zeitwerk::Loader.for_gem
loader.inflector.inflect(
  "cli" => "CLI",
  "json" => "Json",
  "yaml" => "Yaml",
  "mcp" => "MCP",
  "mcp_serve" => "MCPServe",
  "dsl" => "DSL",
  "api" => "API",
)
loader.ignore(File.expand_path("textus/errors.rb", __dir__))
loader.ignore(File.expand_path("textus/init/templates", __dir__))
loader.ignore(File.expand_path("textus/protocol/init/templates", __dir__))
loader.ignore(File.expand_path("textus/protocol/action_registry/verbs", __dir__))
loader.setup
loader.eager_load

Textus::Protocol::Boot::CLI_VERBS = Textus::Protocol::Boot::Catalog.build.freeze
