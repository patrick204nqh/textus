module Textus
  module Protocol
    class Container
      attr_reader :store, :layout, :manifest, :schemas,
                  :workflows, :gate, :root, :ttl_evaluator

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

      def gate=(g)
        @gate = g
      end
    end
  end
end
