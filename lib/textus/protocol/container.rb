module Textus
  module Protocol
    class Container
      attr_accessor :gate
      attr_reader :store, :layout, :manifest, :schemas, :workflows, :root, :ttl_evaluator

      def initialize(store:, layout:, manifest:, schemas:,
                     workflows:,
                     root: nil, gate: nil, ttl_evaluator: nil)
        @store = store
        @layout = layout
        @manifest = manifest
        @schemas = schemas
        @workflows = workflows
        @root = root
        @gate = gate
        @ttl_evaluator = ttl_evaluator
      end
    end
  end
end
