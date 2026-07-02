module Textus
  class Store
    class Container
      Storage    = Data.define(:file_system, :entry_store, :layout)
      Events     = Data.define(:event_store, :workflows)
      Governance = Data.define(:manifest, :schemas)
      Logging    = Data.define(:audit_log)
      Links      = Data.define(:link_graph)

      attr_reader :storage, :events, :governance, :logging, :links, :pipeline

      def initialize(storage:, events:, governance:, logging:, links:, pipeline: nil)
        @storage = storage
        @events = events
        @governance = governance
        @logging = logging
        @links = links
        @pipeline = pipeline
        freeze
      end

      def with_pipeline(pipeline)
        self.class.new(storage:, events:, governance:, logging:, links:, pipeline:)
      end

      def to_h
        {
          file_system: storage.file_system,
          entry_store: storage.entry_store,
          layout: storage.layout,
          event_store: events.event_store,
          workflows: events.workflows,
          manifest: governance.manifest,
          schemas: governance.schemas,
          audit_log: logging.audit_log,
          link_graph: links.link_graph,
        }
      end
    end
  end
end
