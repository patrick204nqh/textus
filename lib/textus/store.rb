require "fileutils"

module Textus
  class Store
    attr_reader :ctx, :container, :role, :correlation_id, :cursor, :propose_lane, :contract_etag, :root

    %i[manifest file_store schemas audit_log job_store layout link_edge_store workflows].each do |field|
      define_method(field) { @ctx.public_send(field) }
    end

    DOMAIN_VERBS = (VerbRegistry::ENTRY_VERBS + VerbRegistry::OPS_VERBS + VerbRegistry::RULE_VERBS).to_set.freeze

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

    def initialize(root, role: Value::Role::DEFAULT, correlation_id: nil, dry_run: false)
      @root = File.expand_path(root)
      @ctx = Store::Builder.new.call(@root)
      @container = build_container_proxy(@ctx)
      @role = role.to_s
      @correlation_id = correlation_id || SecureRandom.uuid
      @dry_run = dry_run
      build_session!
    end

    def dry_run? = @dry_run

    def method_missing(name, *args, **kwargs)
      return super unless DOMAIN_VERBS.include?(name)

      raise ArgumentError.new("#{name} accepts keyword arguments only") unless args.empty?

      spec = VerbRegistry.for(name)
      raise NoMethodError.new("unknown verb: #{name}") unless spec

      pending = Dispatch::Binder.command(spec, kwargs)
      call_obj = Value::Call.build(role: @role, correlation_id: @correlation_id)
      result = @ctx.pipeline.dispatch(pending, call: call_obj)
      Value::Result.extract(result)
    end

    def respond_to_missing?(name, include_private = false)
      DOMAIN_VERBS.include?(name) || super
    end

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

    private

    def _rebuild(role: @role, correlation_id: @correlation_id, dry_run: @dry_run)
      self.class.allocate.tap do |s|
        s.instance_variable_set(:@root, @root)
        s.instance_variable_set(:@ctx, @ctx)
        s.instance_variable_set(:@container, @container)
        s.instance_variable_set(:@role, role.to_s)
        s.instance_variable_set(:@correlation_id, correlation_id || SecureRandom.uuid)
        s.instance_variable_set(:@dry_run, dry_run)
        s.send(:build_session!)
      end
    end

    def build_session!
      @cursor = @ctx.audit_log.latest_seq
      @propose_lane = @ctx.manifest.policy.propose_lane_for(@role)
      @contract_etag = Value::Etag.for_contract(@root)
    end

    def short_etag(etag) = etag.to_s.delete_prefix("sha256:")[0, 8]

    def build_container_proxy(ctx)
      Store::UseCaseContainer.new(
        manifest: ctx.manifest, file_store: ctx.file_store,
        schemas: ctx.schemas, audit_log: ctx.audit_log,
        job_store: ctx.job_store, layout: ctx.layout,
        link_edge_store: ctx.link_edge_store,
        workflows: ctx.workflows, pipeline: ctx.pipeline,
        root: ctx.layout.root
      )
    end
  end
end
