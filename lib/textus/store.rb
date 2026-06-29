require "fileutils"

module Textus
  class Store
    attr_reader :container, :role, :correlation_id, :cursor, :propose_lane, :contract_etag

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

    def initialize(root, role: Value::Role::DEFAULT, correlation_id: nil, dry_run: false, container: nil)
      @root = File.expand_path(root)
      @container = container || build_container(@root)
      @role = role.to_s
      @correlation_id = correlation_id || SecureRandom.uuid
      @dry_run = dry_run
      build_session!
    end

    def dry_run? = @dry_run

    def with_role(new_role)
      _rebuild(role: new_role)
    end

    def with_correlation_id(cid)
      _rebuild(correlation_id: cid)
    end

    def advance_cursor(new_cursor)
      dup.tap do |s|
        s.instance_variable_set(:@cursor, new_cursor)
      end
    end

    def check_etag!(observed_etag)
      return if observed_etag == @contract_etag

      raise Textus::ContractDrift.new(
        "contract changed (manifest/hooks/schemas were #{short_etag(@contract_etag)}, " \
        "now #{short_etag(observed_etag)}); re-run boot",
      )
    end

    def method_missing(name, *args, **kwargs)
      spec = VerbRegistry.for(name)
      return super unless spec

      positional_names = VerbRegistry.positional_for(name)
      if args.size > positional_names.size
        raise ArgumentError.new("#{name} accepts #{positional_names.size} positional argument(s) (got #{args.size})")
      end

      positional_inputs = positional_names.zip(args).to_h.compact
      inputs = positional_inputs.merge(kwargs)
      Dispatch.dispatch(
        container: @container, spec:, inputs:,
        role: @role, correlation_id: @correlation_id
      )
    end

    def respond_to_missing?(name, include_private = false)
      VerbRegistry.for(name) || super
    end

    private

    def _rebuild(role: @role, correlation_id: @correlation_id, dry_run: @dry_run)
      self.class.allocate.tap do |s|
        s.instance_variable_set(:@root, @root)
        s.instance_variable_set(:@container, @container)
        s.instance_variable_set(:@role, role.to_s)
        s.instance_variable_set(:@correlation_id, correlation_id || SecureRandom.uuid)
        s.instance_variable_set(:@dry_run, dry_run)
        s.send(:build_session!)
      end
    end

    def build_session!
      @cursor = @container.audit_log.latest_seq
      @propose_lane = @container.manifest.policy.propose_lane_for(@role)
      @contract_etag = Value::Etag.for_contract(@root)
    end

    def short_etag(etag) = etag.to_s.delete_prefix("sha256:")[0, 8]

    def build_container(root)
      manifest = Manifest.load(root)
      job_store = Port::Store.new(root: root).setup!
      geometry = Store::Geometry.new(root)
      infra = Container::Infrastructure.new(
        file_store: Port::Storage::FileStore.new,
        schemas: Schema::Registry.new(geometry.schemas_dir),
        audit_log: Port::AuditLog.new(
          geometry: geometry,
          max_size: manifest.data.audit_config[:max_size],
          keep: manifest.data.audit_config[:keep],
        ),
        job_store:,
        geometry:,
      )

      coord_seed = Container::Coordination.new(
        manifest:,
        workflows: Workflow::Loader.load_all(root),
        pipeline: nil,
      )

      Container.build(infra, coord_seed)
    end
  end
end
