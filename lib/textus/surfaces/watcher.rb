# frozen_string_literal: true

require "securerandom"

module Textus
  module Surfaces
    class Watcher
      def initialize(container:)
        @container = container
      end

      def tick
        store = Textus::Ports::Store.new(root: @container.root).setup!
        queue = Textus::Jobs::Queue.new(store: store)
        Textus::Jobs::Planner.seed(
          container: @container,
          queue: queue,
          role: Textus::Role::AUTOMATION,
        )
        queue.reclaim(now: Textus::Ports::Clock.new.now)
        Textus::Jobs::Worker.for(container: @container, queue: queue).drain
      ensure
        store&.close
      end

      def run(poll: nil)
        interval = poll || @container.manifest.data.worker_config[:poll]
        lock = Textus::Ports::WatcherLock.new(@container.root)
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
