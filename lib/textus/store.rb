require "fileutils"
require "securerandom"

module Textus
  class Store
    attr_reader :root, :manifest, :registry, :reader, :writer, :bus

    # A Textus UID: 16 lowercase hex chars (SecureRandom.hex(8)). Not a UUID —
    # short on purpose. Random enough for collision-never-in-practice within a
    # single store.
    def self.mint_uid
      SecureRandom.hex(8)
    end

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
      fire_event(:loaded)
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

    def get(key, as: "script")
      bus = Infra::EventBus.new(registry: registry)
      worker = Application::Refresh::Worker.new(store: self, bus: bus)
      orchestrator = Application::Refresh::Orchestrator.new(
        worker: worker, bus: bus, store_root: root, store: self,
      )
      result = Application::Reads::Get.new(store: self, orchestrator: orchestrator).call(key, as: as)
      raise UnknownKey.new(key, suggestions: manifest.suggestions_for(key)) if result.nil?

      result
    end

    def where(key) = @reader.where(key)
    def list(**) = @reader.list(**)
    def schema_envelope(key) = @reader.schema_envelope(key)

    def put(...) = @writer.put(...)

    def delete(...) = @writer.delete(...)

    def fire_event(event, **)
      view = Store::View.new(self)
      @bus.publish(event, store: view, **)
    end

    def accept(...) = @writer.accept(...)
    def reject(...) = @writer.reject(...)

    def deps(key)    = @reader.deps(key)
    def rdeps(key)   = @reader.rdeps(key)
    def published    = @reader.published
    def stale(**)    = @reader.stale(**)
    def validate_all = @reader.validate_all

    def uid(key) = @reader.uid(key)

    # Move an entry from old_key to new_key within the same zone. Preserves
    # uid (minting one first if absent), validates both keys against the
    # manifest, refuses to clobber, and writes one mv audit row.
    def mv(old_key, new_key, as: Role::DEFAULT, dry_run: false)
      Mover.new(store: self, reader: @reader, writer: @writer, manifest: @manifest, audit_log: audit_log)
           .call(old_key, new_key, as: as, dry_run: dry_run)
    end

    def audit_log
      @audit_log ||= Store::AuditLog.new(@root)
    end
  end
end
