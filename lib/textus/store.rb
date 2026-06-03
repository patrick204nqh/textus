require "fileutils"

module Textus
  class Store
    attr_reader :root, :manifest, :schemas, :file_store, :audit_log, :events, :rpc

    def self.discover(start_dir = Dir.pwd, root: nil)
      explicit = root || ENV.fetch("TEXTUS_ROOT", nil)
      return discover_explicit(explicit) if explicit

      ascend_for_store(File.expand_path(start_dir)) ||
        raise(IoError.new("no .textus directory found from #{start_dir}"))
    end

    private_class_method def self.ascend_for_store(dir)
      loop do
        candidate = File.join(dir, ".textus")
        return new(candidate) if store_dir?(candidate)

        parent = File.dirname(dir)
        return nil if parent == dir

        dir = parent
      end
    end

    private_class_method def self.discover_explicit(root_arg)
      abs = File.expand_path(root_arg)
      raise IoError.new("no textus store at #{abs}") unless store_dir?(abs)

      new(abs)
    end

    private_class_method def self.store_dir?(dir)
      File.directory?(dir) && File.exist?(File.join(dir, "manifest.yaml"))
    end

    def initialize(root)
      @root       = File.expand_path(root)
      @manifest   = Manifest.load(@root)
      @schemas    = Schemas.new(File.join(@root, "schemas"))
      @file_store = Ports::Storage::FileStore.new
      @audit_log  = Ports::AuditLog.new(
        @root,
        max_size: @manifest.data.audit_config[:max_size],
        keep: @manifest.data.audit_config[:keep],
      )
      @events = Hooks::EventBus.new
      @rpc = Hooks::RpcRegistry.new
      Ports::AuditSubscriber.new(@audit_log).attach(@events)
      Hooks::Builtin.register_all(events: @events, rpc: @rpc)
      Hooks::Loader.new(events: @events, rpc: @rpc).load_dir(File.join(@root, "hooks"))
      @events.publish(:store_loaded, ctx: Hooks::Context.new(scope: as(Role::DEFAULT)))
    end

    def container
      @container ||= Textus::Container.from_store(self)
    end

    # Build an agent Session oriented at the current cursor/manifest — the
    # Ruby equivalent of an MCP `initialize`. ADR 0036.
    def session(role:)
      Textus::Session.new(
        role: role,
        cursor: audit_log.latest_seq,
        propose_zone: manifest.policy.propose_zone_for(role),
        manifest_etag: file_store.etag(File.join(root, "manifest.yaml")),
      )
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
