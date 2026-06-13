module Textus
  module Maintenance
    class Watch
      def initialize(container:, call:)
        @container = container
        @call = call
        @queue = Textus::Ports::Queue.new(root: container.root)
      end

      def tick
        Textus::Jobs::Scheduler.new(container: @container, queue: @queue).run_once
        @queue.reclaim(now: Textus::Ports::Clock.new.now)
        Worker.for(container: @container, queue: @queue).drain
      end

      def run(poll: nil)
        interval = poll || @container.manifest.data.worker_config[:poll]
        loop do
          tick
          sleep(interval)
        end
      end
    end
  end
end
