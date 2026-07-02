module Textus
  class Store
    class Builder
      def call(root)
        manifest = Manifest.load(root)
        database = Port::Database.new(root: root).setup!
        event_store = Store::EventStore.new(database)
        layout = Store::Layout.new(root)
        file_system = Store::FileSystem.new
        schemas = Schema::Registry.new(layout.schemas_dir)
        audit_log = Port::AuditLog.new(
          layout:,
          max_size: manifest.data.audit_config[:max_size],
          keep: manifest.data.audit_config[:keep],
        )
        link_edge_store = Links::LinkEdgeStore.new(database)

        workflows = Workflow::Loader.load_all(root)
        workflows.concat([Textus::Workflows::Materialize, Textus::Workflows::Index])

        ttl_evaluator = Store::Freshness::TtlEvaluator.new(
          manifest:,
          file_stat: file_system,
          clock: Port::Clock.new,
        )

        trace_buffer = Store::TraceBuffer.new

        entry_store = Store::EntryStore.new(file_system:, manifest:, audit_log:, layout:)

        partial = Infrastructure.new(
          manifest:, file_system:, schemas:, audit_log:,
          database:, event_store:, entry_store:,
          layout:, link_edge_store:, workflows:, root:,
          reader: entry_store, writer: entry_store,
          ttl_evaluator:, trace_buffer:, pipeline: nil
        )

        middleware = [
          Dispatch::Middleware::Binder.new,
          Dispatch::Middleware::Trace.new,
          Dispatch::Middleware::Auth.new,
        ]

        Dispatch::HandlerResolver.eager_load!

        interim_pipeline = Dispatch::Pipeline.new(registry: Dispatch::HandlerResolver.build(partial), container: partial, middleware:)
        wired = partial.with(pipeline: interim_pipeline)
        registry = Dispatch::HandlerResolver.build(wired)
        wired.with(pipeline: Dispatch::Pipeline.new(registry:, container: wired, middleware:))
      end
    end
  end
end
