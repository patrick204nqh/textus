module Textus
  module Protocol
    class Container
      attr_accessor :gate
      attr_reader :store, :layout, :manifest, :schemas, :workflows, :workflow_registry, :root, :ttl_evaluator, :store_engine

      def initialize(store:, layout:, manifest:, schemas:,
                     workflows:, workflow_registry: nil,
                     root: nil, gate: nil, ttl_evaluator: nil, store_engine: nil)
        @store = store
        @layout = layout
        @manifest = manifest
        @schemas = schemas
        @workflows = workflows
        @workflow_registry = workflow_registry
        @root = root
        @gate = gate
        @ttl_evaluator = ttl_evaluator
        @store_engine = store_engine
      end
    end
  end
end
