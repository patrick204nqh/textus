module Textus
  # Single canonical entrypoint for invoking application use-cases against a
  # store. Mirrors the directory structure under `lib/textus/application/`:
  #
  #   ops = Textus::Operations.for(store, role: "agent")
  #   ops.writes.put.call(key, body: "...")
  #   ops.reads.get.call(key)
  #   ops.refresh.worker.call(key)
  #
  # Replaces the prior `Textus::Composition` module (deleted in v0.12.2).
  class Operations
    def self.for(store, role: Role::DEFAULT, correlation_id: nil, dry_run: false)
      ctx = Application::Context.new(
        store: store,
        role: role,
        correlation_id: correlation_id,
        dry_run: dry_run,
      )
      new(ctx)
    end

    attr_reader :ctx

    def initialize(ctx)
      @ctx = ctx
    end

    def writes
      @writes ||= Writes.new(@ctx)
    end

    def reads
      @reads ||= Reads.new(@ctx)
    end

    def refresh
      @refresh ||= Refresh.new(@ctx)
    end

    def with_role(role)
      self.class.new(@ctx.with_role(role))
    end
  end
end
