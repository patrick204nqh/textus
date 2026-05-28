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
        ports: Application::Ports.from_store(store),
        boot: -> { Textus::Boot.run(store) },
        doctor: -> { Textus::Doctor.run(store) },
      )
    end

    attr_reader :ctx, :ports

    def initialize(ctx:, ports:, boot: nil, doctor: nil)
      @ctx    = ctx
      @ports  = ports
      @boot   = boot   || -> { {} }
      @doctor = doctor || -> { { "ok" => true, "issues" => [] } }
      @authorizer = Textus::Domain::Authorizer.new(manifest: @ports.manifest)
    end

    def with_role(role)
      self.class.new(ctx: @ctx.with_role(role), ports: @ports, boot: @boot, doctor: @doctor)
    end

    def hook_context
      @hook_context ||= Textus::Hooks::Context.new(ops: self)
    end

    # writes
    def put(...)
      Application::Writes::Put.new(
        ctx: @ctx, ports: @ports, writer: envelope_writer,
        authorizer: @authorizer, hook_context: hook_context
      ).call(...)
    end

    def delete(...)
      Application::Writes::Delete.new(
        ctx: @ctx, ports: @ports, writer: envelope_writer,
        authorizer: @authorizer, hook_context: hook_context
      ).call(...)
    end

    def mv(...)
      Application::Writes::Mv.new(
        ctx: @ctx, ports: @ports,
        reader: envelope_reader, writer: envelope_writer,
        authorizer: @authorizer, hook_context: hook_context
      ).call(...)
    end

    def accept(...)
      Application::Writes::Accept.new(
        ctx: @ctx, ports: @ports, writer: envelope_writer,
        authorizer: @authorizer, hook_context: hook_context
      ).call(...)
    end

    def reject(...)
      Application::Writes::Reject.new(
        ctx: @ctx, ports: @ports, writer: envelope_writer,
        authorizer: @authorizer, hook_context: hook_context
      ).call(...)
    end

    def publish(...)
      Application::Writes::Publish.new(
        ctx: @ctx, ports: @ports, boot: @boot, hook_context: hook_context,
      ).call(...)
    end

    # reads
    def get(...) = Application::Reads::Get.new(ctx: @ctx, ports: @ports).call(...)

    def get_or_refresh(...)
      Application::Reads::GetOrRefresh.new(
        ports: @ports,
        get: Application::Reads::Get.new(ctx: @ctx, ports: @ports),
        orchestrator: orchestrator,
      ).call(...)
    end

    def list(...)            = Application::Reads::List.new(ports: @ports).call(...)
    def where(...)           = Application::Reads::Where.new(ports: @ports).call(...)
    def uid(...)             = Application::Reads::Uid.new(ctx: @ctx, ports: @ports).call(...)
    def schema_envelope(...) = Application::Reads::SchemaEnvelope.new(ports: @ports).call(...)
    def deps(...)            = Application::Reads::Deps.new(ports: @ports).call(...)
    def rdeps(...)           = Application::Reads::Rdeps.new(ports: @ports).call(...)
    def published(...)       = Application::Reads::Published.new(ports: @ports).call(...)
    def stale(...)           = Application::Reads::Stale.new(ports: @ports).call(...)
    def audit(...)           = Application::Reads::Audit.new(ports: @ports).call(...)
    def blame(...)           = Application::Reads::Blame.new(ports: @ports).call(...)
    def policy_explain(...)  = Application::Reads::PolicyExplain.new(ports: @ports).call(...)
    def freshness(...)       = Application::Reads::Freshness.new(ctx: @ctx, ports: @ports).call(...)

    def pulse(...)
      Application::Reads::Pulse.new(ctx: @ctx, ports: @ports, doctor: @doctor).call(...)
    end

    def validate_all(...)
      Application::Reads::ValidateAll.new(ctx: @ctx, ports: @ports).call(...)
    end

    # refresh
    def refresh(key) = refresh_worker.run(key)

    def refresh_all(**)
      Application::Refresh::All.new(
        ctx: @ctx, ports: @ports, writer: envelope_writer,
        authorizer: @authorizer, hook_context: hook_context
      ).call(**)
    end

    # restructure
    def key_mv_prefix(**)
      Application::Restructure::KeyMvPrefix.new(ctx: @ctx, ports: @ports, operations: self).call(**)
    end

    def key_delete_prefix(**)
      Application::Restructure::KeyDeletePrefix.new(ctx: @ctx, ports: @ports, operations: self).call(**)
    end

    def zone_mv(**)
      Application::Restructure::ZoneMv.new(ctx: @ctx, ports: @ports).call(**)
    end

    def rule_lint(**)
      Application::Restructure::RuleLint.new(ctx: @ctx, ports: @ports).call(**)
    end

    def migrate(**)
      Application::Restructure::Migrate.new(ctx: @ctx, ports: @ports, operations: self).call(**)
    end

    private

    def envelope_reader
      @envelope_reader ||= Application::Writes::EnvelopeReader.new(
        file_store: @ports.file_store,
        manifest: @ports.manifest,
      )
    end

    def envelope_writer
      @envelope_writer ||= Application::Writes::EnvelopeWriter.new(
        file_store: @ports.file_store,
        manifest: @ports.manifest,
        schemas: @ports.schemas,
        audit_log: @ports.audit_log,
        ctx: @ctx,
        reader: envelope_reader,
      )
    end

    def refresh_worker
      @refresh_worker ||= Application::Refresh::Worker.new(
        ctx: @ctx, ports: @ports, writer: envelope_writer,
        authorizer: @authorizer, hook_context: hook_context
      )
    end

    def orchestrator
      @orchestrator ||= Application::Refresh::Orchestrator.new(
        worker: refresh_worker,
        store_root: @ports.root,
        bus: @ports.event_bus,
        ctx: @ctx,
        hook_context: hook_context,
      )
    end
  end
end
