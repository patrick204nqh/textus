module Textus
  module Protocol
    class Builder
      def call(root)
        manifest    = Manifest.load(root)
        layout      = Protocol::Layout.new(root)
        database    = Infra::Database.new(layout:).setup!
        file_system = Infra::FileSystem.new
        schemas     = Protocol::Schema::Registry.new(layout.schemas_dir)

        store       = Infra::Store.new(database:, file_system:)
        workflows   = Workflow::Registry.load_all(root)
        workflow_registry = Workflow::Registry.new(workflows)

        event_emitter = Textus::Workflow::EventEmitter.new(
          store.workflow_queue,
          registry: workflow_registry,
        )

        store_engine = StoreEngine.new(
          file_system:, manifest:, layout:, store:, event_emitter:, schemas:,
        )

        ttl_evaluator = Protocol::Freshness::TtlEvaluator.new(
          manifest:,
          file_stat: file_system,
          clock: Infra::Clock.new,
        )

        container = Container.new(
          store:, layout:,
          manifest:, schemas:,
          workflows:, workflow_registry:,
          root:, ttl_evaluator:
        )

        gate = Protocol::Gate.new(
          manifest:,
          resolver: manifest.resolver,
          container:,
          store_engine:,
        )

        container.gate = gate
        container
      end
    end
  end
end
