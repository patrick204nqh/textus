module Textus
  module Protocol
    class Builder
      class Runtime
        Components = Data.define(:store_engine, :gate, :ttl_evaluator, :container, :session_store)

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

          session_store = SessionStore.new(infra.database.connection)

          gate = Gate.new(
            store_engine:,
            container: nil,
            session_store:,
          )

          container = Container.new(
            store: infra.store, layout: infra.layout,
            manifest: domain.manifest, schemas: domain.schemas,
            workflows: domain.workflows,
            store_engine:,
            root:, ttl_evaluator:,
            gate:, session_store:
          )

          gate.container = container
          container.gate = gate
          container.session_store = session_store

          Components.new(store_engine:, gate:, ttl_evaluator:, container:, session_store:)
        end
      end
    end
  end
end
