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
