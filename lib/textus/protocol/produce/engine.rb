require "set"

module Textus
  module Protocol
    module Produce
      class Engine
        IN_FLIGHT = Set.new
        IN_FLIGHT_MUTEX = Mutex.new

        def self.converging?(key) = IN_FLIGHT.include?(key)

        def self.converge(container:, call:, keys:)
          new(container:, call:).run(keys)
        end

        def initialize(container:, call:)
          @container = container
          @call      = call
          @workflow_registry = container.workflow_registry || Textus::Workflow::Registry.new(container.workflows)
        end

        def run(keys)
          results = { completed: [], failed: [] }
          Array(keys).each do |key|
            IN_FLIGHT_MUTEX.synchronize { IN_FLIGHT.add(key) }
            record_outcome(produce_one(key), results)
            IN_FLIGHT_MUTEX.synchronize { IN_FLIGHT.delete(key) }
          end
          results
        end

        alias call run

        private

        def produce_one(key)
          workflow = @workflow_registry.match_for_key(key)
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
          return unless entry.publish_tree || @container.store.file_system.exists?(
            @container.manifest.resolver.resolve(key).path,
          )

          es = Protocol::EntryStore.new(
            file_system: @container.store.file_system,
            manifest: @container.manifest,
            layout: @container.layout,
            store: @container.store,
          )
          pctx = Textus::Protocol::Manifest::Entry::Base::PublishContext.new(
            container: @container, call: @call,
            reader: es.method(:read)
          )
          entry.publish_via(pctx)
        end
      end
    end
  end
end
