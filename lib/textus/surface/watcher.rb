# frozen_string_literal: true

require "securerandom"

module Textus
  module Surface
    class Watcher
      CONSUMER = Textus::Events::Consumer.new

      def initialize(container:)
        @container = container
        @registry = Textus::Workflow::Registry.new(container.workflows)
      end

      def tick
        CONSUMER.drain(
          db: @container.event_store.db,
          registry: @registry,
          container: @container,
          call: Textus::Value::Call.build(role: Textus::Value::Role::AUTOMATION, correlation_id: SecureRandom.uuid),
        )
      end

      def run(poll: nil)
        interval = poll || @container.manifest.data.worker_config[:poll] || 2
        lock = Textus::Port::WatcherLock.new(@container.root)
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
