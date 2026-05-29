module Textus
  # Per-call session. Holds ctx (role, correlation_id, now, dry_run) and
  # the three caps records. Generates one method per registered use case.
  class Session
    attr_reader :ctx, :read_caps, :write_caps, :hook_caps

    def self.for(store, role: Role::DEFAULT, correlation_id: nil, dry_run: false)
      read_caps, write_caps, hook_caps = Application.caps_from_store(store)
      new(
        ctx: Application::Context.build(role: role, correlation_id: correlation_id, dry_run: dry_run),
        read_caps: read_caps, write_caps: write_caps, hook_caps: hook_caps
      )
    end

    def initialize(ctx:, read_caps:, write_caps:, hook_caps:)
      @ctx        = ctx
      @read_caps  = read_caps
      @write_caps = write_caps
      @hook_caps  = hook_caps
    end

    def with_role(role)
      self.class.new(
        ctx: @ctx.with_role(role),
        read_caps: @read_caps, write_caps: @write_caps, hook_caps: @hook_caps
      )
    end

    def hook_context
      @hook_context ||= Hooks::Context.new(session: self)
    end

    def rpc = @hook_caps.rpc
    def events = @hook_caps.events

    def envelope_reader
      @envelope_reader ||= Application::Envelope::Reader.new(
        file_store: @read_caps.file_store, manifest: @read_caps.manifest,
      )
    end

    def envelope_writer
      @envelope_writer ||= Application::Envelope::Writer.new(
        file_store: @write_caps.file_store, manifest: @write_caps.manifest,
        schemas: @write_caps.schemas, audit_log: @write_caps.audit_log,
        ctx: @ctx, reader: envelope_reader
      )
    end

    def boot(...) = Textus::Boot.run(self, ...)
    def doctor(...) = Textus::Doctor.run(self, ...)

    def refresh_orchestrator
      @refresh_orchestrator ||= Application::Write::RefreshOrchestrator.new(
        worker: refresh_worker,
        store_root: @write_caps.root,
        events: @write_caps.events,
        ctx: @ctx,
        hook_context: hook_context,
      )
    end

    def refresh_worker
      @refresh_worker ||= Application::Write::RefreshWorker::Impl.new(
        ctx: @ctx, caps: @write_caps,
        rpc: rpc, writer: envelope_writer, hook_context: hook_context
      )
    end

    # Generated dispatch methods. Defined AFTER all use-cases have registered
    # (Zeitwerk.eager_load runs in lib/textus.rb, then session.rb is explicitly
    # required so UseCase.entries is fully populated).
    Application::UseCase.each do |entry|
      verb     = entry.verb
      mod      = entry.mod
      caps_sym = entry.caps_kind

      define_method(verb) do |*args, **kwargs|
        if mod.is_a?(Class)
          container = Textus::Container.from_store_caps(@read_caps, @write_caps, @hook_caps)
          call_value = Textus::Call.new(
            role: @ctx.role, correlation_id: @ctx.correlation_id,
            now: @ctx.now, dry_run: @ctx.dry_run
          )
          init_kwargs = { container: container, call: call_value, hook_context: hook_context }
          # Use cases that need to re-enter the verb dispatcher (Publish,
          # RefreshOrchestrator, RefreshAll) accept an optional session: kwarg.
          params = mod.instance_method(:initialize).parameters.map { |_, n| n }
          init_kwargs[:session] = self if params.include?(:session)
          mod.new(**init_kwargs).call(*args, **kwargs)
        else
          fixed = { session: self, ctx: @ctx, caps: caps_sym == :read ? @read_caps : @write_caps }
          mod.call(*args, **fixed, **kwargs)
        end
      end
    end
  end
end
