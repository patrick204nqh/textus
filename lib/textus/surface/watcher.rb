require "securerandom"

module Textus
  module Surface
    class Watcher
      def initialize(container:)
        @container = container
        @registry = Textus::Workflow::Registry.new(container.workflows)
      end

      def tick
        call = Textus::Value::Call.build(role: Textus::Value::Role::AUTOMATION, correlation_id: SecureRandom.uuid)

        Textus::Workflow::Scheduler.new(
          registry: @registry,
          workflow_queue: @container.store.workflow_queue,
          reader: ->(key:) { @container.store_engine.read(key:) },
        ).seed_expired

        consumer = Textus::Workflow::Consumer.new(registry: @registry, container: @container, call:)
        loop do
          row = @container.store.workflow_queue.pop
          break unless row
          consumer.consume(row, @container.store.workflow_queue)
        end
      end

      def run(poll: nil)
        interval = poll || @container.manifest.data.worker_config[:poll] || 2
        lock = Infra::Locks::WatcherLock.new(@container.root)
        lock.acquire
        begin
          loop do
            tick
            sleep(interval)
          end
        ensure
          lock.release
        end
      end
    end
  end
end
