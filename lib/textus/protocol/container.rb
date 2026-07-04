module Textus
  module Protocol
    class Container
      attr_reader :file_system, :entry_store, :layout, :entry_index,
                  :event_store, :workflows,
                  :manifest, :schemas,
                  :audit_log,
                  :link_graph,
                  :gate, :root, :ttl_evaluator

      # rubocop:disable Metrics/ParameterLists
      def initialize(file_system:, entry_store:, layout:, entry_index:,
                     event_store:, workflows:,
                     manifest:, schemas:,
                     audit_log:,
                     link_graph:,
                      root: nil, gate: nil, ttl_evaluator: nil)
        @file_system = file_system
        @entry_store = entry_store
        @layout = layout
        @entry_index = entry_index
        @event_store = event_store
        @workflows = workflows
        @manifest = manifest
        @schemas = schemas
        @audit_log = audit_log
        @link_graph = link_graph
        @root = root
        @gate = gate
        @ttl_evaluator = ttl_evaluator
      end

      def gate=(g)
        @gate = g
      end
      # rubocop:enable Metrics/ParameterLists

      def to_h
        {
          file_system:, entry_store:, layout:, entry_index:,
          event_store:, workflows:,
          manifest:, schemas:,
          audit_log:,
          link_graph:,
        }
      end

      def link_edge_store = link_graph
      def reader          = entry_store
      def writer          = entry_store
    end
  end
end
