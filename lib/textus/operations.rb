module Textus
  # Single canonical entrypoint for invoking application use-cases against a
  # store. Public surface is flat — one method per use case:
  #
  #   ops = Textus::Operations.for(store, role: "agent")
  #   ops.put(key, body: "...")
  #   ops.get(key)               # pure read
  #   ops.get_or_refresh(key)    # read + refresh-on-stale
  #   ops.refresh(key)           # synchronous worker refresh
  #   ops.refresh_all(prefix: ..., zone: ...)
  class Operations
    def self.for(store, role: Role::DEFAULT, correlation_id: nil, dry_run: false)
      new(
        ctx: Application::Context.build(role: role, correlation_id: correlation_id, dry_run: dry_run),
        manifest: store.manifest,
        file_store: store.file_store,
        schemas: store.schemas,
        audit_log: store.audit_log,
        bus: store.bus,
        root: store.root,
        store: store,
      )
    end

    attr_reader :ctx, :store

    # rubocop:disable Metrics/ParameterLists
    def initialize(ctx:, manifest:, file_store:, schemas:, audit_log:, bus:, root:, store:)
      @ctx        = ctx
      @manifest   = manifest
      @file_store = file_store
      @schemas    = schemas
      @audit_log  = audit_log
      @bus        = bus
      @root       = root
      @store      = store
      @authorizer = Textus::Domain::Authorizer.new(manifest: @manifest)
    end
    # rubocop:enable Metrics/ParameterLists

    def with_role(role)
      self.class.new(
        ctx: @ctx.with_role(role),
        manifest: @manifest, file_store: @file_store, schemas: @schemas,
        audit_log: @audit_log, bus: @bus,
        root: @root, store: @store
      )
    end

    def hook_context
      @hook_context ||= Textus::Hooks::Context.new(ops: self)
    end

    # writes
    def put(...)
      Application::Writes::Put.new(
        ctx: @ctx, manifest: @manifest, envelope_io: envelope_io,
        bus: @bus, authorizer: @authorizer, hook_context: hook_context
      ).call(...)
    end

    def delete(...)
      Application::Writes::Delete.new(
        ctx: @ctx, manifest: @manifest, envelope_io: envelope_io,
        bus: @bus, authorizer: @authorizer, hook_context: hook_context
      ).call(...)
    end

    def mv(...)
      Application::Writes::Mv.new(
        ctx: @ctx, manifest: @manifest, envelope_io: envelope_io,
        bus: @bus, authorizer: @authorizer, hook_context: hook_context
      ).call(...)
    end

    def accept(...)
      Application::Writes::Accept.new(
        ctx: @ctx, manifest: @manifest, file_store: @file_store, schemas: @schemas,
        envelope_io: envelope_io, bus: @bus, authorizer: @authorizer, hook_context: hook_context
      ).call(...)
    end

    def reject(...)
      Application::Writes::Reject.new(
        ctx: @ctx, manifest: @manifest, file_store: @file_store,
        envelope_io: envelope_io, bus: @bus, authorizer: @authorizer, hook_context: hook_context
      ).call(...)
    end

    def publish(...)
      Application::Writes::Publish.new(
        ctx: @ctx, manifest: @manifest, file_store: @file_store,
        bus: @bus, root: @root, store: @store, hook_context: hook_context
      ).call(...)
    end

    # reads
    def get(...)
      Application::Reads::Get.new(ctx: @ctx, manifest: @manifest, file_store: @file_store).call(...)
    end

    def get_or_refresh(...)
      Application::Reads::GetOrRefresh.new(
        manifest: @manifest,
        get: Application::Reads::Get.new(ctx: @ctx, manifest: @manifest, file_store: @file_store),
        orchestrator: orchestrator,
      ).call(...)
    end

    def list(...)            = Application::Reads::List.new(manifest: @manifest).call(...)
    def where(...)           = Application::Reads::Where.new(manifest: @manifest).call(...)
    def uid(...)             = Application::Reads::Uid.new(ctx: @ctx, manifest: @manifest, file_store: @file_store).call(...)
    def schema_envelope(...) = Application::Reads::SchemaEnvelope.new(manifest: @manifest, schemas: @schemas).call(...)
    def deps(...)            = Application::Reads::Deps.new(manifest: @manifest).call(...)
    def rdeps(...)           = Application::Reads::Rdeps.new(manifest: @manifest).call(...)
    def published(...)       = Application::Reads::Published.new(manifest: @manifest).call(...)
    def stale(...)           = Application::Reads::Stale.new(manifest: @manifest).call(...)
    def audit(...)           = Application::Reads::Audit.new(manifest: @manifest, root: @root, audit_log: @audit_log).call(...)
    def blame(...)           = Application::Reads::Blame.new(manifest: @manifest, root: @root).call(...)
    def policy_explain(...)  = Application::Reads::PolicyExplain.new(manifest: @manifest).call(...)
    def freshness(...)       = Application::Reads::Freshness.new(ctx: @ctx, manifest: @manifest, file_store: @file_store).call(...)

    def pulse(...)
      Application::Reads::Pulse.new(
        ctx: @ctx, manifest: @manifest, file_store: @file_store,
        audit_log: @audit_log, root: @root, store: @store
      ).call(...)
    end

    def validate_all(...)
      Application::Reads::ValidateAll.new(
        ctx: @ctx, manifest: @manifest, file_store: @file_store, schemas: @schemas, audit_log: @audit_log,
      ).call(...)
    end

    # refresh
    def refresh(key) = refresh_worker.run(key)

    def refresh_all(**)
      Application::Refresh::All.new(
        ctx: @ctx, manifest: @manifest, envelope_io: envelope_io, bus: @bus,
        store: @store, authorizer: @authorizer, hook_context: hook_context
      ).call(**)
    end

    private

    def envelope_io
      @envelope_io ||= Application::Writes::EnvelopeIO.new(
        file_store: @file_store,
        manifest: @manifest,
        schemas: @schemas,
        audit_log: @audit_log,
        ctx: @ctx,
      )
    end

    def refresh_worker
      @refresh_worker ||= Application::Refresh::Worker.new(
        ctx: @ctx, manifest: @manifest, envelope_io: envelope_io, bus: @bus,
        store: @store, authorizer: @authorizer, hook_context: hook_context
      )
    end

    def orchestrator
      @orchestrator ||= Application::Refresh::Orchestrator.new(
        worker: refresh_worker,
        store_root: @root,
        bus: @bus,
        store: @store,
        ctx: @ctx,
        hook_context: hook_context,
      )
    end
  end
end
