module Textus
  module Composition
    module_function

    def context(store, role:, correlation_id: nil, dry_run: false)
      Textus::Application::Context.new(
        store: store,
        role: role,
        correlation_id: correlation_id,
        dry_run: dry_run,
      )
    end

    def reads_get(ctx)
      Textus::Application::Reads::Get.new(ctx: ctx, orchestrator: refresh_orchestrator(ctx))
    end

    def refresh_worker(ctx)
      Textus::Application::Refresh::Worker.new(ctx: ctx, bus: ctx.store.bus)
    end

    def refresh_orchestrator(ctx)
      Textus::Application::Refresh::Orchestrator.new(
        worker: refresh_worker(ctx),
        bus: ctx.store.bus,
        store_root: ctx.store.root,
        store: ctx.store,
      )
    end

    def writes_put(ctx)
      Textus::Application::Writes::Put.new(ctx: ctx, bus: ctx.store.bus)
    end

    def writes_delete(ctx)
      Textus::Application::Writes::Delete.new(ctx: ctx, bus: ctx.store.bus)
    end

    def writes_build(ctx)
      Textus::Application::Writes::Build.new(ctx: ctx, bus: ctx.store.bus)
    end

    def writes_accept(ctx)
      Textus::Application::Writes::Accept.new(ctx: ctx, bus: ctx.store.bus)
    end

    def writes_publish(ctx)
      Textus::Application::Writes::Publish.new(ctx: ctx, bus: ctx.store.bus)
    end

    def event_bus(ctx)
      Textus::Infra::EventBus.new(registry: ctx.store.registry)
    end
  end
end
