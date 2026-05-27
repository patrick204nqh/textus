require "fileutils"

module Textus
  class Store
    attr_reader :root, :manifest, :schemas, :file_store, :audit_log, :bus, :registry

    def self.discover(start_dir = Dir.pwd, root: nil)
      explicit = root || ENV.fetch("TEXTUS_ROOT", nil)
      return discover_explicit(explicit) if explicit

      dir = File.expand_path(start_dir)
      loop do
        candidate = File.join(dir, ".textus")
        return new(candidate) if File.directory?(candidate) && File.exist?(File.join(candidate, "manifest.yaml"))

        parent = File.dirname(dir)
        break if parent == dir

        dir = parent
      end
      raise IoError.new("no .textus directory found from #{start_dir}")
    end

    private_class_method def self.discover_explicit(root_arg)
      abs = File.expand_path(root_arg)
      raise IoError.new("no textus store at #{abs}") unless File.directory?(abs) && File.exist?(File.join(abs, "manifest.yaml"))

      new(abs)
    end

    def initialize(root)
      @root       = File.expand_path(root)
      @manifest   = Manifest.load(@root)
      @schemas    = Schemas.new(File.join(@root, "schemas"))
      @file_store = Infra::Storage::FileStore.new
      @audit_log  = Infra::AuditLog.new(@root)
      @bus        = Hooks::Dispatcher.new
      @registry   = Hooks::Registry.new(dispatcher: @bus)
      Infra::AuditSubscriber.new(@audit_log).attach(@bus)
      Hooks::Builtin.register_all(@registry)
      Hooks::Loader.new(registry: @registry).load_dir(File.join(@root, "hooks"))
      @bus.publish(:store_loaded, store: self)
    end
  end
end
