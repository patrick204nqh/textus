module Textus
  module Protocol
    class Builder
      class Runtime
        Components = Data.define(:store_engine, :gate, :ttl_evaluator, :container)

        def call(infra:, domain:, root:)
          event_emitter = Textus::Workflow::EventEmitter.new(
            infra.store.workflow_queue,
            registry: domain.workflow_registry,
          )

          store_engine = StoreEngine.new(
            file_system: infra.file_system, manifest: domain.manifest,
            layout: infra.layout, store: infra.store,
            event_emitter:, schemas: domain.schemas
          )

          ttl_evaluator = Freshness::TtlEvaluator.new(
            manifest: domain.manifest,
            file_stat: infra.file_system,
            clock: Infra::Clock.new,
          )

          container = Container.new(
            store: infra.store, layout: infra.layout,
            manifest: domain.manifest, schemas: domain.schemas,
            workflows: domain.workflows,
            workflow_registry: domain.workflow_registry,
            store_engine: store_engine,
            root:, ttl_evaluator:
          )

          gate = Gate.new(
            manifest: domain.manifest,
            resolver: domain.manifest.resolver,
            container:,
            store_engine:,
          )

          container.gate = gate
          Components.new(store_engine:, gate:, ttl_evaluator:, container:)
        end
      end
    end
  end
end
