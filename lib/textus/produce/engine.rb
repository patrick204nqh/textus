module Textus
  module Produce
    class Engine
      def self.converge(container:, call:, keys:)
        new(container:, call:).run(keys)
      end

      def initialize(container:, call:)
        @container = container
        @call      = call
      end

      def run(keys)
        results = { completed: [], failed: [] }
        Array(keys).each { |key| produce_one(key, results) }
        results
      end

      private

      def produce_one(key, results)
        workflow = @container.workflows.for(key)
        raise Textus::Workflow::NotFound.new(key) unless workflow

        Workflow::Runner.new(workflow, container: @container, call: @call).run(key)
        results[:completed] << key
      rescue StandardError => e
        results[:failed] << { key: key, error: e.message }
      end
    end
  end
end
