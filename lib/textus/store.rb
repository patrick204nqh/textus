require "fileutils"

module Textus
  class Store
    attr_reader :root, :manifest, :registry, :reader, :writer, :bus

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
      @bus = Hooks::Dispatcher.new(audit_log: audit_log)
      @registry = Hooks::Registry.new(dispatcher: @bus)
      @schemas = {}
      load_hooks
      @reader = Reader.new(self)
      @writer = Writer.new(self)
      @bus.publish(:store_loaded, store: Textus::Application::Context.system(self))
    end

    def load_hooks
      Textus.with_registry(@registry) do
        Hooks::Builtin.register_all
        dir = File.join(@root, "hooks")
        return unless File.directory?(dir)

        Dir.glob(File.join(dir, "**/*.rb")).sort.each do |f| # rubocop:disable Lint/RedundantDirGlobSort
          begin
            load(f)
          rescue StandardError, ScriptError => e
            raise UsageError.new("failed loading hook #{File.basename(f)}: #{e.class}: #{e.message}")
          end
        end
      end
    end

    def schema_for(name)
      return nil if name.nil?

      @schemas[name] ||= begin
        sp = File.join(@root, "schemas", "#{name}.yaml")
        raise IoError.new("schema not found: #{sp}") unless File.exist?(sp)

        Schema.load(sp)
      end
    end

    def audit_log
      @audit_log ||= Store::AuditLog.new(@root)
    end
  end
end
