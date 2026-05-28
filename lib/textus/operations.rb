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
      read_caps, write_caps, hook_caps = Application.caps_from_store(store)
      new(
        ctx: Application::Context.build(role: role, correlation_id: correlation_id, dry_run: dry_run),
        read_caps: read_caps,
        write_caps: write_caps,
        hook_caps: hook_caps,
        boot: -> { Textus::Boot.run(store) },
        doctor: -> { Textus::Doctor.run(store) },
      )
    end

    attr_reader :ctx, :read_caps, :write_caps, :hook_caps

    def initialize(ctx:, read_caps:, write_caps:, hook_caps:, boot: nil, doctor: nil)
      @ctx        = ctx
      @read_caps  = read_caps
      @write_caps = write_caps
      @hook_caps  = hook_caps
      @boot       = boot   || -> { {} }
      @doctor     = doctor || -> { { "ok" => true, "issues" => [] } }
    end

    def with_role(role)
      self.class.new(
        ctx: @ctx.with_role(role),
        read_caps: @read_caps,
        write_caps: @write_caps,
        hook_caps: @hook_caps,
        boot: @boot,
        doctor: @doctor,
      )
    end

    def hook_context
      @hook_context ||= Textus::Hooks::Context.new(ops: self)
    end

    # writes
    def put(...)
      Application::Writes::Put.new(
        ctx: @ctx, caps: @write_caps, writer: envelope_writer,
        hook_context: hook_context
      ).call(...)
    end

    def delete(...)
      Application::Writes::Delete.new(
        ctx: @ctx, caps: @write_caps, writer: envelope_writer,
        hook_context: hook_context
      ).call(...)
    end

    def mv(...)
      Application::Writes::Mv.new(
        ctx: @ctx, caps: @write_caps,
        reader: envelope_reader, writer: envelope_writer,
        hook_context: hook_context
      ).call(...)
    end

    def accept(...)
      Application::Writes::Accept.new(
        ctx: @ctx, caps: @write_caps, writer: envelope_writer,
        hook_context: hook_context
      ).call(...)
    end

    def reject(...)
      Application::Writes::Reject.new(
        ctx: @ctx, caps: @write_caps, writer: envelope_writer,
        hook_context: hook_context
      ).call(...)
    end

    def publish(...)
      Application::Writes::Publish.new(
        ctx: @ctx, caps: @write_caps, rpc: @hook_caps.rpc,
        boot: @boot, hook_context: hook_context
      ).call(...)
    end

    # reads
    def get(...) = Application::Reads::Get.new(ctx: @ctx, caps: @read_caps).call(...)

    def get_or_refresh(...)
      Application::Reads::GetOrRefresh.new(
        caps: @read_caps,
        get: Application::Reads::Get.new(ctx: @ctx, caps: @read_caps),
        orchestrator: orchestrator,
      ).call(...)
    end

    def list(...)            = Application::Reads::List.new(caps: @read_caps).call(...)
    def where(...)           = Application::Reads::Where.new(caps: @read_caps).call(...)
    def uid(...)             = Application::Reads::Uid.new(ctx: @ctx, caps: @read_caps).call(...)
    def schema_envelope(...) = Application::Reads::SchemaEnvelope.new(caps: @read_caps).call(...)
    def deps(...)            = Application::Reads::Deps.new(caps: @read_caps).call(...)
    def rdeps(...)           = Application::Reads::Rdeps.new(caps: @read_caps).call(...)
    def published(...)       = Application::Reads::Published.new(caps: @read_caps).call(...)
    def stale(...)           = Application::Reads::Stale.new(caps: @read_caps).call(...)
    def audit(...)           = Application::Reads::Audit.new(caps: @read_caps).call(...)
    def blame(...)           = Application::Reads::Blame.new(caps: @read_caps).call(...)
    def policy_explain(...)  = Application::Reads::PolicyExplain.new(caps: @read_caps).call(...)
    def freshness(...)       = Application::Reads::Freshness.new(ctx: @ctx, caps: @read_caps).call(...)

    def pulse(...)
      Application::Reads::Pulse.new(ctx: @ctx, caps: @read_caps, doctor: @doctor).call(...)
    end

    def validate_all(...)
      Application::Reads::ValidateAll.new(ctx: @ctx, caps: @read_caps).call(...)
    end

    # refresh
    def refresh(key) = refresh_worker.run(key)

    def refresh_all(**)
      Application::Refresh::All.new(
        ctx: @ctx, caps: @write_caps, rpc: @hook_caps.rpc, writer: envelope_writer,
        hook_context: hook_context
      ).call(**)
    end

    # restructure
    def key_mv_prefix(**)
      Application::Restructure::KeyMvPrefix.new(ctx: @ctx, caps: @write_caps, operations: self).call(**)
    end

    def key_delete_prefix(**)
      Application::Restructure::KeyDeletePrefix.new(ctx: @ctx, caps: @write_caps, operations: self).call(**)
    end

    def zone_mv(**)
      Application::Restructure::ZoneMv.new(ctx: @ctx, caps: @write_caps).call(**)
    end

    def rule_lint(**)
      Application::Restructure::RuleLint.new(ctx: @ctx, caps: @write_caps).call(**)
    end

    def migrate(**)
      Application::Restructure::Migrate.new(ctx: @ctx, caps: @write_caps, operations: self).call(**)
    end

    private

    def envelope_reader
      @envelope_reader ||= Application::Envelope::Reader.new(
        file_store: @read_caps.file_store,
        manifest: @read_caps.manifest,
      )
    end

    def envelope_writer
      @envelope_writer ||= Application::Envelope::Writer.new(
        file_store: @write_caps.file_store,
        manifest: @write_caps.manifest,
        schemas: @write_caps.schemas,
        audit_log: @write_caps.audit_log,
        ctx: @ctx,
        reader: envelope_reader,
      )
    end

    def refresh_worker
      @refresh_worker ||= Application::Refresh::Worker.new(
        ctx: @ctx, caps: @write_caps, rpc: @hook_caps.rpc,
        writer: envelope_writer, hook_context: hook_context
      )
    end

    def orchestrator
      @orchestrator ||= Application::Refresh::Orchestrator.new(
        worker: refresh_worker,
        store_root: @read_caps.root,
        events: @hook_caps.events,
        ctx: @ctx,
        hook_context: hook_context,
      )
    end
  end
end
