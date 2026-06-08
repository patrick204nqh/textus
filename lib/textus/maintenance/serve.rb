module Textus
  module Maintenance
    # The convergence daemon loop: seed scheduled work (TTL re-pull + sweep),
    # reclaim crashed leases, drain the queue, sleep, repeat. `tick` is one
    # iteration (unit-testable); `run` loops forever. Drains serially for the
    # same reason as Drain — each produce job self-locks, so running them in turn
    # keeps the build lock uncontended.
    class Serve
      def initialize(container:, call:)
        @container = container
        @call = call
        @queue = Textus::Ports::Queue.new(root: container.root)
      end

      def tick
        Textus::Jobs::Scheduler.new(container: @container, queue: @queue).run_once
        @queue.reclaim(now: Textus::Ports::Clock.new.now)
        worker.drain
      end

      def run(poll: nil)
        interval = poll || @container.manifest.data.worker_config[:poll]
        loop do
          tick
          sleep(interval)
        end
      end

      private

      def worker
        Textus::Maintenance::Worker.new(
          queue: @queue, registry: Textus::Jobs::Handlers.registry,
          container: @container, lease_ttl: @container.manifest.data.worker_config[:lease_ttl]
        )
      end
    end
  end
end
