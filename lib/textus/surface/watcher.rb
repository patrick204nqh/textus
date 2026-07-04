require "securerandom"

module Textus
  module Surface
    class Watcher
      def initialize(container:)
        @container = container
        @queue = Protocol::Async::Queue.new(container.store.event_store)
        @registry = Textus::Workflow::Registry.new(container.workflows)
      end

      def tick
        call = Textus::Value::Call.build(role: Textus::Value::Role::AUTOMATION, correlation_id: SecureRandom.uuid)
        loop do
          row = @queue.consume_one(registry: @registry, container: @container, call:)
          break unless row
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
