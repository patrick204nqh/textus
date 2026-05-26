module Textus
  class Operations
    class Reads
      def initialize(ctx)
        @ctx = ctx
      end

      def get
        Application::Reads::Get.new(ctx: @ctx, orchestrator: orchestrator)
      end

      def freshness      = Application::Reads::Freshness.new(ctx: @ctx)
      def audit          = Application::Reads::Audit.new(ctx: @ctx)
      def blame          = Application::Reads::Blame.new(ctx: @ctx)
      def policy_explain = Application::Reads::PolicyExplain.new(ctx: @ctx)
      def list           = Application::Reads::List.new(ctx: @ctx)
      def where           = Application::Reads::Where.new(ctx: @ctx)
      def uid             = Application::Reads::Uid.new(ctx: @ctx)
      def schema_envelope = Application::Reads::SchemaEnvelope.new(ctx: @ctx)
      def deps            = Application::Reads::Deps.new(ctx: @ctx)
      def rdeps           = Application::Reads::Rdeps.new(ctx: @ctx)
      def published       = Application::Reads::Published.new(ctx: @ctx)
      def stale           = Application::Reads::Stale.new(ctx: @ctx)
      def validate_all    = Application::Reads::ValidateAll.new(ctx: @ctx)

      private

      def orchestrator
        Application::Refresh::Orchestrator.new(
          worker: Application::Refresh::Worker.new(ctx: @ctx, bus: @ctx.store.bus),
          bus: @ctx.store.bus,
          store_root: @ctx.store.root,
          store: @ctx.store,
          role: @ctx.role,
        )
      end
    end
  end
end
