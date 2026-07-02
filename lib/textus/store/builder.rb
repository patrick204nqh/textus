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
        link_edge_store = Links::LinkEdgeStore.new(db: job_store)
        workflows = Workflow::Loader.load_all(root)
        event_bus = Event::Bus.new

        ttl_evaluator = Store::Freshness::TtlEvaluator.new(
          manifest:,
          file_stat: Port::Storage::FileStat.new,
          clock: Port::Clock.new,
        )

        trace_buffer = Store::TraceBuffer.new

        cascade_subscriber = Produce::CascadeSubscriber.new(
          manifest:, workflows:, job_store:, file_store:,
        )
        event_bus.subscribe(Event::EntryWritten,     &cascade_subscriber.method(:on_entry_written))
        event_bus.subscribe(Event::EntryDeleted,     &cascade_subscriber.method(:on_entry_deleted))
        event_bus.subscribe(Event::EntryMoved,       &cascade_subscriber.method(:on_entry_moved))
        event_bus.subscribe(Event::ProposalAccepted, &cascade_subscriber.method(:on_proposal_accepted))
        event_bus.subscribe(Event::ProposalRejected, &cascade_subscriber.method(:on_proposal_rejected))

        reader  = Store::Entry::Reader.new(file_store:, manifest:, layout:)
        writer  = Store::Entry::Writer.new(file_store:, manifest:, schemas:,
                                           audit_log:, reader:, layout:)

        partial = Infrastructure.new(
          manifest:, file_store:, schemas:, audit_log:, job_store:,
          layout:, link_edge_store:, workflows:, root:,
          reader:, writer:, event_bus:,
          ttl_evaluator:, trace_buffer:, pipeline: nil
        )

        middleware = [
          Dispatch::Middleware::Binder.new,
          Dispatch::Middleware::Trace.new,
          Dispatch::Middleware::Auth.new,
          Dispatch::Middleware::AuditIndex.new(job_store: partial.job_store, audit_log: partial.audit_log),
        ]

        Dispatch::HandlerResolver.eager_load!

        # NEEDS deps are snapshotted at HandlerResolver.build time, so a handler
        # declaring :pipeline in NEEDS (DoctorStore, to dispatch sub-checks like
        # `list`/`get` against a live pipeline) would otherwise always see the
        # `pipeline: nil` from `partial` above. Build once against `partial` to
        # get a working pipeline, wire it into the container, then rebuild the
        # registry against that container so :pipeline resolves to a real value.
        interim_pipeline = Dispatch::Pipeline.new(registry: Dispatch::HandlerResolver.build(partial), container: partial, middleware:)
        wired = partial.with(pipeline: interim_pipeline)
        registry = Dispatch::HandlerResolver.build(wired)
        wired.with(pipeline: Dispatch::Pipeline.new(registry:, container: wired, middleware:))
      end
    end
  end
end
