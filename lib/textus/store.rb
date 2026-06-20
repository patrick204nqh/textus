require "fileutils"

module Textus
  class Store
    attr_reader :container

    # Readers are derived from the Container's schema, so the field set lives
    # in exactly one place (Container). A new capability added there is
    # automatically exposed on the Store.
    Textus::Container.attribute_names.each do |field|
      define_method(field) { @container.public_send(field) }
    end

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
      @container = build_container(File.expand_path(root))
    end

    # Build an agent Session oriented at the current cursor/manifest — the
    # Ruby equivalent of an MCP `initialize`. ADR 0036.
    def session(role:)
      Textus::Session.new(
        role: role.to_s,
        cursor: audit_log.latest_seq,
        propose_lane: manifest.policy.propose_lane_for(role),
        contract_etag: Textus::Etag.for_contract(root),
      )
    end

    def gate
      @container.gate
    end

    def as(role, dry_run: false, correlation_id: nil)
      Textus::Surface::RoleScope.new(container: container, role: role, dry_run: dry_run, correlation_id: correlation_id)
    end

    private

    def build_container(root)
      manifest = Manifest.load(root)
      container = Container.new(
        root: root,
        manifest: manifest,
        schemas: Schemas.new(File.join(root, "schemas")),
        file_store: Port::Storage::FileStore.new,
        audit_log: Port::AuditLog.new(
          root,
          max_size: manifest.data.audit_config[:max_size],
          keep: manifest.data.audit_config[:keep],
        ),
        workflows: Workflow::Loader.load_all(root),
        gate: nil,
      )
      gate = Textus::Gate.new(container)
      container = container.with(gate: gate)
      gate.instance_variable_set(:@container, container)
      container
    end
  end
end
