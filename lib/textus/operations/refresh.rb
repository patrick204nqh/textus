module Textus
  class Operations
    class Refresh
      def initialize(ctx)
        @ctx = ctx
      end

      def worker
        Application::Refresh::Worker.new(ctx: @ctx, bus: @ctx.store.bus)
      end

      def orchestrator
        Application::Refresh::Orchestrator.new(
          worker: worker,
          bus: @ctx.store.bus,
          store_root: @ctx.store.root,
          store: @ctx.store,
          role: @ctx.role,
        )
      end

      def all
        Application::Refresh::All.new(ctx: @ctx, bus: @ctx.store.bus)
      end
    end
  end
end
