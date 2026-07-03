require "ostruct"

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

        gate = Protocol::Gate.new(
          manifest:,
          resolver: manifest.resolver,
          pipeline: OpenStruct.new(container:),
        )

        container.class.new(
          storage: container.storage, events: container.events,
          governance: container.governance, logging: container.logging,
          links: container.links, root: container.root,
          pipeline: OpenStruct.new(container:), gate:,
          trace_buffer: container.trace_buffer,
          ttl_evaluator: container.ttl_evaluator,
        )
      end
    end
  end
  end
end
