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
        Array(keys).each { |key| record_outcome(produce_one(key), results) }
        results
      end

      alias call run

      private

      def produce_one(key)
        workflow = @container.workflows.find { |d| d.match?(key) }
        if workflow
          Workflow::Runner.new(workflow, container: @container, call: @call).run(key)
        else
          publish_only(key)
        end
        Textus::Value::Outcome::Completed.new(details: { key: key })
      rescue StandardError => e
        Textus::Value::Outcome::DeadLettered.new(error: { key: key, message: e.message })
      end

      def record_outcome(outcome, results)
        case outcome
        when Textus::Value::Outcome::Completed
          results[:completed] << outcome.details[:key]
        when Textus::Value::Outcome::DeadLettered
          results[:failed] << {
            key: outcome.error[:key],
            error: outcome.error[:message],
          }
        end
      end

      def publish_only(key)
        entry = @container.manifest.resolver.resolve(key).entry
        return unless entry.publish_tree || !Array(entry.publish_to).empty?
        return unless entry.publish_tree || @container.file_system.exists?(
          @container.manifest.resolver.resolve(key).path,
        )

        pctx = Textus::Manifest::Entry::Base::PublishContext.new(
          container: @container, call: @call,
          reader: @container.entry_store.method(:read)
        )
        entry.publish_via(pctx)
      end
    end
  end
end
