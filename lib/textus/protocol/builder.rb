module Textus
  module Protocol
    class Builder
      def call(root)
        manifest    = Manifest.load(root)
        database    = Infra::Database.new(root: root).setup!
        event_store = Protocol::Events::EventStore.new(database)
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
        entry_store = Protocol::EntryStore.new(file_system: file_store, manifest:, audit_log:, layout:, entry_index:)

        ttl_evaluator = Protocol::Freshness::TtlEvaluator.new(
          manifest:,
          file_stat: file_store,
          clock: Infra::Clock.new,
        )

        container = Container.new(
          file_system: file_store, entry_store:, layout:, entry_index:,
          event_store:, workflows:,
          manifest:, schemas:,
          audit_log:,
          link_graph:,
          root:, ttl_evaluator:
        )

        gate = Protocol::Gate.new(
          manifest:,
          resolver: manifest.resolver,
          container:,
        )

        container.gate = gate
        container
      end
    end
  end
end
