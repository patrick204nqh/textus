require "zeitwerk"
require_relative "textus/version"
require_relative "textus/errors"

loader = Zeitwerk::Loader.for_gem
loader.inflector.inflect(
  "cli" => "CLI",
  "json" => "Json",
  "yaml" => "Yaml",
  "hook_dsl_scanner" => "HookDSLScanner",
  "envelope_io" => "EnvelopeIO",
)
loader.ignore(File.expand_path("textus/errors.rb", __dir__))
loader.setup
loader.eager_load

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
