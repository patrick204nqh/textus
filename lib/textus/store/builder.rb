module Textus
  class Store
    class Builder
      def call(root)
        manifest = Manifest.load(root)
        job_store = Port::Store.new(root: root).setup!
        layout = Store::Layout.new(root)
        file_store = Port::Storage::FileStore.new
        schemas = Schema::Registry.new(layout.schemas_dir)
        audit_log = Port::AuditLog.new(
          layout:,
          max_size: manifest.data.audit_config[:max_size],
          keep: manifest.data.audit_config[:keep],
        )
        link_edge_store = Links::LinkEdgeStore.new(database: job_store)

        workflows = Workflow::Loader.load_all(root)
        workflows.concat([Textus::Workflows::Materialize, Textus::Workflows::Index])

        ttl_evaluator = Store::Freshness::TtlEvaluator.new(
          manifest:,
          file_stat: Port::Storage::FileStat.new,
          clock: Port::Clock.new,
        )

        trace_buffer = Store::TraceBuffer.new

        reader  = Store::Entry::Reader.new(file_store:, manifest:, layout:)
        writer  = Store::Entry::Writer.new(file_store:, manifest:,
                                           audit_log:, reader:, layout:)

        partial = Infrastructure.new(
          manifest:, file_store:, schemas:, audit_log:, job_store:,
          layout:, link_edge_store:, workflows:, root:,
          reader:, writer:,
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
