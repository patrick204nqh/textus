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

      alias call run

      private

      def produce_one(key, results)
        workflow = @container.workflows.for(key)
        if workflow
          Workflow::Runner.new(workflow, container: @container, call: @call).run(key)
        else
          publish_only(key)
        end
        results[:completed] << key
      rescue StandardError => e
        results[:failed] << { key: key, error: e.message }
      end

      def publish_only(key)
        Textus::Produce::Publisher.call(container: @container, call: @call, key: key)
      end
    end
  end
end
