require "zeitwerk"
require_relative "textus/version"
require_relative "textus/errors"
require_relative "textus/surface/mcp"
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
loader.ignore(File.expand_path("textus/surface/mcp.rb", __dir__))
loader.ignore(File.expand_path("textus/surface/mcp/errors.rb", __dir__))
loader.ignore(File.expand_path("textus/workflow/errors.rb", __dir__))
loader.ignore(File.expand_path("textus/init/templates", __dir__))
loader.ignore(File.expand_path("textus/produce/acquire", __dir__))
loader.setup
loader.eager_load

Textus::Boot::CLI_VERBS = Textus::Boot.build_cli_verbs.freeze

Textus::Result = Textus::Value::Result

module Textus
  def self.workflow(name, &)
    collector = Workflow::Collector.current
    raise "Textus.workflow called outside Workflow::Loader.load_all context" unless collector

    defn = Workflow::DSL::Definition.new(name)
    defn.instance_eval(&)
    collector.register(defn)
  end
end
