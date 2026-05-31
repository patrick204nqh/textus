require "zeitwerk"
require_relative "textus/version"
require_relative "textus/errors"
require_relative "textus/mcp"
require_relative "textus/mcp/errors"

loader = Zeitwerk::Loader.for_gem
loader.inflector.inflect(
  "cli" => "CLI",
  "json" => "Json",
  "yaml" => "Yaml",
  "hook_dsl_scanner" => "HookDSLScanner",
  "io" => "IO",
  "mcp" => "MCP",
  "mcp_serve" => "MCPServe",
)
loader.ignore(File.expand_path("textus/errors.rb", __dir__))
loader.ignore(File.expand_path("textus/mcp.rb", __dir__))
loader.ignore(File.expand_path("textus/mcp/errors.rb", __dir__))
loader.setup
loader.eager_load

# Derive CLI_VERBS after eager_load so all contract-declaring files are present
# (boot.rb loads first alphabetically; Dispatcher contracts are declared later).
Textus::Boot::CLI_VERBS = Textus::Boot.build_cli_verbs.freeze

module Textus
  @hook_mutex  = Mutex.new
  @hook_blocks = []

  def self.hook(&blk)
    raise UsageError.new("hook block required") unless blk

    @hook_mutex.synchronize { @hook_blocks << blk }
  end

  def self.drain_hook_blocks
    @hook_mutex.synchronize do
      blocks = @hook_blocks
      @hook_blocks = []
      blocks
    end
  end
end
