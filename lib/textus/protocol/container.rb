module Textus
  module Protocol
    class Container
      attr_accessor :gate, :session_store
      attr_reader :store, :layout, :manifest, :schemas, :workflows, :workflow_registry, :root, :ttl_evaluator, :store_engine

      def initialize(store:, layout:, manifest:, schemas:, workflows:,
                     root: nil, gate: nil, session_store: nil,
                     ttl_evaluator: nil, store_engine: nil)
        @store = store
        @layout = layout
        @manifest = manifest
        @schemas = schemas
        @workflows = workflows
        @workflow_registry = workflows ? Textus::Workflow::Registry.new(workflows) : nil
        @root = root
        @gate = gate
        @session_store = session_store
        @ttl_evaluator = ttl_evaluator
        @store_engine = store_engine
      end
    end
  end
end
