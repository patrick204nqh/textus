module Textus
  class Store
    class Builder
      def call(root)
        manifest    = Manifest.load(root)
        database    = Port::Database.new(root: root).setup!
        event_store = Store::EventStore.new(database)
        layout      = Store::Layout.new(root)
        file_system = Store::FileSystem.new
        schemas     = Schema::Registry.new(layout.schemas_dir)
        audit_log   = Port::AuditLog.new(
          layout:,
          max_size: manifest.data.audit_config[:max_size],
          keep: manifest.data.audit_config[:keep],
        )
        link_graph  = Store::LinkGraph.new(database)
        workflows   = Workflow::Loader.load_all(root)
        workflows.concat([Textus::Workflows::Materialize, Textus::Workflows::Index])
        entry_store = Store::EntryStore.new(file_system:, manifest:, audit_log:, layout:)

        ttl_evaluator = Store::Freshness::TtlEvaluator.new(
          manifest:,
          file_stat: file_system,
          clock: Port::Clock.new,
        )

        trace_buffer = Store::TraceBuffer.new

        storage    = Container::Storage.new(file_system:, entry_store:, layout:)
        events     = Container::Events.new(event_store:, workflows:)
        governance = Container::Governance.new(manifest:, schemas:)
        logging    = Container::Logging.new(audit_log:)
        links      = Container::Links.new(link_graph:)

        container = Container.new(storage:, events:, governance:, logging:, links:, root:)

        middleware = [
          Dispatch::Middleware::Binder.new,
          Dispatch::Middleware::Trace.new,
          Dispatch::Middleware::Auth.new,
        ]

        Dispatch::HandlerResolver.eager_load!
        interim = container.with_pipeline(
          Dispatch::Pipeline.new(
            registry: Dispatch::HandlerResolver.build(container),
            container:, middleware:
          )
        )
        registry = Dispatch::HandlerResolver.build(interim)
        container.with_pipeline(
          Dispatch::Pipeline.new(registry:, container: interim, middleware:)
        )
      end
    end
  end
end
