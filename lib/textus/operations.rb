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

    def with_role(role) = self.class.new(@ctx.with_role(role))

    # writes
    def put(...)     = put_op.call(...)
    def delete(...)  = delete_op.call(...)
    def mv(...)      = mv_op.call(...)
    def accept(...)  = accept_op.call(...)
    def reject(...)  = reject_op.call(...)
    def build(...)   = build_op.call(...)
    def publish(...) = publish_op.call(...)

    # reads
    def get(...)             = get_op.call(...)
    def get_or_refresh(...)  = get_or_refresh_op.call(...)
    def list(...)            = list_op.call(...)
    def where(...)           = where_op.call(...)
    def uid(...)             = uid_op.call(...)
    def schema_envelope(...) = schema_envelope_op.call(...)
    def deps(...)            = deps_op.call(...)
    def rdeps(...)           = rdeps_op.call(...)
    def published(...)       = published_op.call(...)
    def stale(...)           = stale_op.call(...)
    def audit(...)           = audit_op.call(...)
    def blame(...)           = blame_op.call(...)
    def policy_explain(...)  = policy_explain_op.call(...)
    def freshness(...)       = freshness_op.call(...)
    def validate_all(...)    = validate_all_op.call(...)

    # refresh
    def refresh(key) = refresh_worker_op.run(key)
    def refresh_all(**) = Application::Refresh::All.call(@ctx, **)

    private

    def bus = @ctx.store.bus

    def put_op     = @put_op ||= Application::Writes::Put.new(ctx: @ctx, bus: bus)
    def delete_op  = @delete_op ||= Application::Writes::Delete.new(ctx: @ctx, bus: bus)
    def mv_op      = @mv_op ||= Application::Writes::Mv.new(ctx: @ctx, bus: bus)
    def accept_op  = @accept_op ||= Application::Writes::Accept.new(ctx: @ctx, bus: bus)
    def reject_op  = @reject_op ||= Application::Writes::Reject.new(ctx: @ctx, bus: bus)
    def build_op   = @build_op ||= Application::Writes::Build.new(ctx: @ctx, bus: bus)
    def publish_op = @publish_op ||= Application::Writes::Publish.new(ctx: @ctx, bus: bus)

    def get_op = @get_op ||= Application::Reads::Get.new(ctx: @ctx) # rubocop:disable Naming/AccessorMethodName

    def get_or_refresh_op # rubocop:disable Naming/AccessorMethodName
      @get_or_refresh_op ||= Application::Reads::GetOrRefresh.new(ctx: @ctx, get: get_op,
                                                                  orchestrator: orchestrator_op)
    end

    def list_op            = @list_op ||= Application::Reads::List.new(ctx: @ctx)
    def where_op           = @where_op ||= Application::Reads::Where.new(ctx: @ctx)
    def uid_op             = @uid_op ||= Application::Reads::Uid.new(ctx: @ctx)
    def schema_envelope_op = @schema_envelope_op ||= Application::Reads::SchemaEnvelope.new(ctx: @ctx)
    def deps_op            = @deps_op ||= Application::Reads::Deps.new(ctx: @ctx)
    def rdeps_op           = @rdeps_op ||= Application::Reads::Rdeps.new(ctx: @ctx)
    def published_op       = @published_op ||= Application::Reads::Published.new(ctx: @ctx)
    def stale_op           = @stale_op ||= Application::Reads::Stale.new(ctx: @ctx)
    def audit_op           = @audit_op ||= Application::Reads::Audit.new(ctx: @ctx)
    def blame_op           = @blame_op ||= Application::Reads::Blame.new(ctx: @ctx)
    def policy_explain_op  = @policy_explain_op ||= Application::Reads::PolicyExplain.new(ctx: @ctx)
    def freshness_op       = @freshness_op ||= Application::Reads::Freshness.new(ctx: @ctx)
    def validate_all_op    = @validate_all_op ||= Application::Reads::ValidateAll.new(ctx: @ctx)

    def refresh_worker_op = @refresh_worker_op ||= Application::Refresh::Worker.new(ctx: @ctx, bus: bus)

    def orchestrator_op
      @orchestrator_op ||= Application::Refresh::Orchestrator.new(
        worker: refresh_worker_op,
        bus: bus,
        store_root: @ctx.store.root,
        store: @ctx.store,
        role: @ctx.role,
      )
    end
  end
end
