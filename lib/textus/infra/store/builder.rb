module Textus
  module Infra
  class Store
    class Builder
      def call(root)
        manifest    = Manifest.load(root)
        database    = Infra::Database.new(root: root).setup!
        event_store = Store::EventStore.new(database)
        layout      = Protocol::Layout.new(root)
        file_store  = Infra::FileStore.new
        schemas     = Protocol::Schema::Registry.new(layout.schemas_dir)
        audit_log   = Protocol::Audit.new(
          layout:,
          max_size: manifest.data.audit_config[:max_size],
          keep: manifest.data.audit_config[:keep],
          file_system: file_store,
        )
        link_graph  = Protocol::Links.new(database)
        entry_index = Protocol::Index.new(database)
        workflows   = Workflow::Loader.load_all(root)
        workflows.push(Textus::Workflow::Instances::Materialize)
        entry_store = Store::EntryStore.new(file_system: file_store, manifest:, audit_log:, layout:, entry_index:)

        ttl_evaluator = Store::Freshness::TtlEvaluator.new(
          manifest:,
          file_stat: file_store,
          clock: Infra::Clock.new,
        )

        trace_buffer = Store::TraceBuffer.new

        storage    = Container::Storage.new(file_system: file_store, entry_store:, layout:, entry_index:)
        events     = Container::Events.new(event_store:, workflows:)
        governance = Container::Governance.new(manifest:, schemas:)
        logging    = Container::Logging.new(audit_log:)
        links      = Container::Links.new(link_graph:)

        container = Container.new(
          storage:, events:, governance:, logging:, links:,
          root:, trace_buffer:, ttl_evaluator:
        )

        middleware = [
          Dispatch::Middleware::Binder.new,
          Dispatch::Middleware::Trace.new,
          Dispatch::Middleware::Auth.new,
          Dispatch::Middleware::Events.new,
        ]

        Dispatch::HandlerResolver.eager_load!
        interim = container.with_pipeline(
          Dispatch::Pipeline.new(
            registry: Dispatch::HandlerResolver.build(container),
            container:, middleware:
          ),
        )
        registry = Dispatch::HandlerResolver.build(interim)
        finalized = container.with_pipeline(
          Dispatch::Pipeline.new(registry:, container: interim, middleware:),
        )
        gate = Protocol::Gate.new(
          manifest:,
          resolver: manifest.resolver,
          pipeline: finalized.pipeline,
        )
        finalized.class.new(
          storage: finalized.storage, events: finalized.events,
          governance: finalized.governance, logging: finalized.logging,
          links: finalized.links, root: finalized.root,
          pipeline: finalized.pipeline, gate:,
          trace_buffer: finalized.trace_buffer,
          ttl_evaluator: finalized.ttl_evaluator,
        )
      end
    end
  end
  end
end
