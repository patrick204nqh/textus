module Textus
  class Store
    class Builder
      def call(root)
        manifest    = Manifest.load(root)
        database    = Infra::Database.new(root: root).setup!
        event_store = Store::EventStore.new(database)
        layout      = Store::Layout.new(root)
        file_store  = Infra::FileStore.new
        schemas     = Schema::Registry.new(layout.schemas_dir)
        audit_log   = Port::AuditLog.new(
          layout:,
          max_size: manifest.data.audit_config[:max_size],
          keep: manifest.data.audit_config[:keep],
          file_system: file_store,
        )
        link_graph  = Store::LinkGraph.new(database)
        entry_index = Store::EntryIndex.new(database)
        workflows   = Workflow::Loader.load_all(root)
        workflows.push(Textus::Workflow::Instances::Materialize)
        entry_store = Store::EntryStore.new(file_system: file_store, manifest:, audit_log:, layout:, entry_index:)

        ttl_evaluator = Store::Freshness::TtlEvaluator.new(
          manifest:,
          file_stat: file_store,
          clock: Infra::Clock.new,
        )

        trace_buffer = Store::TraceBuffer.new

        # Protocol layer components
        protocol_manifest = Protocol::Manifest.load(root)
        protocol_layout   = Protocol::Layout.new(root)
        protocol_index    = Protocol::Index.new(database)
        protocol_links    = Protocol::Links.new(database)
        protocol_audit    = Protocol::Audit.new(
          layout: protocol_layout,
          max_size: protocol_manifest.data.audit_config[:max_size],
          keep: protocol_manifest.data.audit_config[:keep],
          file_system: file_store,
        )
        protocol_gate     = Protocol::Gate.new(
          manifest: protocol_manifest,
          resolver: protocol_manifest.resolver,
        )

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
        container.with_pipeline(
          Dispatch::Pipeline.new(registry:, container: interim, middleware:),
        )
      end
    end
  end
end
