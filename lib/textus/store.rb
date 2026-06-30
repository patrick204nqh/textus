require "fileutils"

module Textus
  class Store
    attr_reader :ctx, :container, :role, :correlation_id, :cursor, :propose_lane, :contract_etag, :root

    %i[manifest file_store schemas audit_log job_store layout link_edge_store workflows].each do |field|
      define_method(field) { @ctx.public_send(field) }
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
      @ctx = build_ctx(@root)
      @container = build_container_proxy(@ctx)
      @role = role.to_s
      @correlation_id = correlation_id || SecureRandom.uuid
      @dry_run = dry_run
      build_session!
    end

    def dry_run? = @dry_run

    def entry(verb, **) = _dispatch_in_domain(verb, VerbRegistry::ENTRY_VERBS, **)
    def ops(verb, **)   = _dispatch_in_domain(verb, VerbRegistry::OPS_VERBS, **)
    def rule(verb, **)  = _dispatch_in_domain(verb, VerbRegistry::RULE_VERBS, **)

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

    def _dispatch_in_domain(verb, allowed, **opts)
      raise ArgumentError.new("#{verb} is not in this domain (allowed: #{allowed.first(4).join(", ")}...)") unless allowed.include?(verb)

      spec = VerbRegistry.for(verb)
      raise ArgumentError.new("unknown verb: #{verb}") unless spec

      pending = Dispatch::Binder.command(spec, opts)
      call    = Value::Call.build(role: @role, correlation_id: @correlation_id)
      result  = @ctx.pipeline.dispatch(pending, call: call)
      Value::Result.extract(result)
    end

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

    def build_ctx(root)
      manifest = Manifest.load(root)
      job_store = Port::Store.new(root: root).setup!
      layout = Store::Layout.new(root)
      file_store = Port::Storage::FileStore.new
      schemas = Schema::Registry.new(layout.schemas_dir)
      audit_log = Port::AuditLog.new(
        layout:,
        max_size: manifest.data.audit_config[:max_size],
        keep: manifest.data.audit_config[:keep],
      )
      link_edge_store = Links::LinkEdgeStore.new
      workflows = Workflow::Loader.load_all(root)
      event_bus = Event::Bus.new

      freshness_evaluator = Store::Freshness::TtlEvaluator.new(
        manifest:,
        file_stat: Port::Storage::FileStat.new,
        clock: Port::Clock.new,
      )

      cascade_subscriber = Produce::CascadeSubscriber.new(
        manifest:, workflows:, job_store:, file_store:,
      )
      event_bus.subscribe(Event::EntryWritten,     &cascade_subscriber.method(:on_entry_written))
      event_bus.subscribe(Event::EntryDeleted,     &cascade_subscriber.method(:on_entry_deleted))
      event_bus.subscribe(Event::EntryMoved,       &cascade_subscriber.method(:on_entry_moved))
      event_bus.subscribe(Event::ProposalAccepted, &cascade_subscriber.method(:on_proposal_accepted))
      event_bus.subscribe(Event::ProposalRejected, &cascade_subscriber.method(:on_proposal_rejected))

      orchestration = build_orchestration(
        manifest:, file_store:, schemas:, audit_log:, job_store:, layout:,
      )

      partial = Ctx.new(
        manifest:, file_store:, schemas:, audit_log:, job_store:,
        layout:, link_edge_store:, workflows:, event_bus:,
        freshness_evaluator:, orchestration:, pipeline: nil
      )

      middleware = [
        Dispatch::Middleware::Binder.new,
        Dispatch::Middleware::Auth.new,
        Dispatch::Middleware::AuditIndex.new(job_store: partial.job_store, audit_log: partial.audit_log),
      ]

      Dispatch::HandlerResolver.eager_load!
      registry = Dispatch::HandlerResolver.build(partial)
      pipeline = Dispatch::Pipeline.new(registry:, container: partial, middleware:)

      partial.with(pipeline:)
    end

    def build_orchestration(manifest:, file_store:, schemas:, audit_log:, job_store:, layout:)
      list_deps = Data.define(:manifest, :job_store).new(manifest:, job_store:)
      audit_deps = Data.define(:manifest, :audit_log).new(manifest:, audit_log:)
      move_deps = Data.define(:file_store, :manifest, :schemas, :audit_log, :layout).new(
        file_store:, manifest:, schemas:, audit_log:, layout:,
      )
      delete_deps = Data.define(:file_store, :manifest, :schemas, :audit_log, :layout).new(
        file_store:, manifest:, schemas:, audit_log:, layout:,
      )
      Orchestration.new(
        list_keys: ->(command, call) { Handlers::Read::ListKeys.call(command, call, list_deps) },
        move_key: ->(command, call) { Handlers::Write::MoveKey.call(command, call, move_deps) },
        delete_key: ->(command, call) { Handlers::Write::DeleteKey.call(command, call, delete_deps) },
        audit_entries: ->(command, call) { Handlers::Read::AuditEntries.call(command, call, audit_deps) },
      )
    end

    def build_container_proxy(ctx)
      Store::ContainerProxy.new(
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
