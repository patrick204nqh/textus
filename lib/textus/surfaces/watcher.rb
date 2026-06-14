# frozen_string_literal: true

require "securerandom"

module Textus
  module Surfaces
    class Watcher
      def initialize(container:)
        @container = container
        @queue = Textus::Ports::Queue.new(root: container.root)
      end

      def tick
        Textus::Background::Planner::Planner.seed(
          container: @container,
          queue: @queue,
          role: Textus::Role::AUTOMATION,
        )
        @queue.reclaim(now: Textus::Ports::Clock.new.now)
        Textus::Background::Worker.for(container: @container, queue: @queue).drain
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
