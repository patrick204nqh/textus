require "fileutils"

module Textus
  class Store
    attr_reader :container

    Textus::Store::Container.attribute_names.each do |field|
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

    def query
      @read_model ||= ReadModel.new(@container)
    end

    def command(role:, correlation_id: nil)
      CommandModel.new(bus: @container.pipeline, role: role, correlation_id: correlation_id)
    end

    def session(role:)
      Textus::Store::Session.new(
        role: role.to_s,
        cursor: audit_log.latest_seq,
        propose_lane: manifest.policy.propose_lane_for(role),
        contract_etag: Textus::Value::Etag.for_contract(root),
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
      job_store = Port::Store.new(root: root).setup!
      geometry = Store::Geometry.new(root)
      infra = Container::Infrastructure.new(
        file_store: Port::Storage::FileStore.new,
        schemas: Schemas.new(geometry.schemas_dir),
        audit_log: Port::AuditLog.new(
          root,
          max_size: manifest.data.audit_config[:max_size],
          keep: manifest.data.audit_config[:keep],
        ),
        job_store:,
        geometry:,
      )

      coord_seed = Container::Coordination.new(
        manifest:,
        workflows: Workflow::Loader.load_all(root),
        gate: nil,
        compositor: nil,
        pipeline: nil,
      )

      Container.build_full(infra, coord_seed)
    end
  end
end
