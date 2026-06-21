# frozen_string_literal: true

require "securerandom"

module Textus
  module Surface
    class Watcher
      def initialize(container:)
        @container = container
      end

      def tick
        queue = Textus::Store::Jobs::Queue.new(store: @container.job_store)
        Textus::Store::Jobs::Planner.seed(
          container: @container,
          queue: queue,
          role: Textus::Value::Role::AUTOMATION,
        )
        queue.reclaim(now: Textus::Port::Clock.new.now)
        Textus::Store::Jobs::Worker.for(container: @container, queue: queue).drain
      end

      def run(poll: nil)
        interval = poll || @container.manifest.data.worker_config[:poll]
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
