require "fileutils"

module Textus
  class Store
    attr_reader :root, :manifest, :schemas, :file_store, :audit_log, :events, :rpc

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
      @audit_log  = Infra::AuditLog.new(
        @root,
        max_size: @manifest.data.audit_config[:max_size],
        keep: @manifest.data.audit_config[:keep],
      )
      @events = Hooks::EventBus.new
      @rpc = Hooks::RpcRegistry.new
      Infra::AuditSubscriber.new(@audit_log).attach(@events)
      Hooks::Builtin.register_all(events: @events, rpc: @rpc)
      Hooks::Loader.new(events: @events, rpc: @rpc).load_dir(File.join(@root, "hooks"))
      @events.publish(:store_loaded, ctx: Hooks::Context.new(scope: as(Role::DEFAULT)))
    end

    def session(role: Role::DEFAULT, correlation_id: nil, dry_run: false)
      Session.for(self, role: role, correlation_id: correlation_id, dry_run: dry_run)
    end

    def container
      @container ||= Textus::Container.from_store(self)
    end

    def as(role, dry_run: false, correlation_id: nil)
      RoleScope.new(container: container, role: role, dry_run: dry_run, correlation_id: correlation_id)
    end

    Textus::Dispatcher::VERBS.each_key do |verb|
      define_method(verb) do |*args, role: Role::DEFAULT, **kwargs|
        as(role).public_send(verb, *args, **kwargs)
      end
    end
  end
end
