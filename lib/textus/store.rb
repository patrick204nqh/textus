require "fileutils"

module Textus
  class Store
    attr_reader :root, :manifest, :registry, :reader, :writer, :bus, :schemas, :file_store

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
      @root = File.expand_path(root)
      @manifest = Manifest.load(@root)
      @bus = Hooks::Dispatcher.new
      Textus::Infra::AuditSubscriber.new(audit_log).attach(@bus)
      @registry = Hooks::Registry.new(dispatcher: @bus)
      @schema_cache = {}
      @file_store = Infra::Storage::FileStore.new
      @schemas    = Schemas.new(File.join(@root, "schemas"))
      load_hooks
      @reader = Reader.new(self)
      @writer = Writer.new(self)
      @bus.publish(:store_loaded, store: Textus::Application::Context.system(self))
    end

    def load_hooks
      Hooks::Builtin.register_all(@registry)
      Hooks::Loader.new(registry: @registry).load_dir(File.join(@root, "hooks"))
    end

    def schema_for(name)
      return nil if name.nil?

      @schema_cache[name] ||= begin
        sp = File.join(@root, "schemas", "#{name}.yaml")
        raise IoError.new("schema not found: #{sp}") unless File.exist?(sp)

        Schema.load(sp)
      end
    end

    def audit_log
      @audit_log ||= Textus::Infra::AuditLog.new(@root)
    end
  end
end
