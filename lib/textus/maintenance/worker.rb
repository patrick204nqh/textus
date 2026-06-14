module Textus
  module Maintenance
    # Drains the job queue: lease a job, look up its handler in the registry, run
    # it (as the job's stamped authority — wired in a later phase), then ack on
    # success or fail (requeue/dead-letter) on a raise. `drain` runs until the
    # queue is empty and returns a summary. Delivery is at-least-once.
    class Worker
      Summary = Struct.new(:completed, :failed, keyword_init: true)

      # The standard convergence worker: the closed handler allow-list plus the
      # lease TTL from worker_config. Both `drain` and `serve` build it this way.
      def self.for(container:, queue:)
        new(
          queue: queue, registry: Textus::Dispatch::Planner::Handlers.registry,
          container: container, lease_ttl: container.manifest.data.worker_config[:lease_ttl]
        )
      end

      def initialize(queue:, registry:, container:, lease_ttl: 60)
        @queue = queue
        @registry = registry
        @container = container
        @lease_ttl = lease_ttl
      end

      def drain(worker_id: "drain-#{Process.pid}")
        completed = 0
        failed = 0
        loop do
          leased = @queue.lease(worker_id: worker_id, lease_ttl: @lease_ttl)
          break unless leased

          case run_one(leased)
          when :completed     then completed += 1
          when :dead_lettered then failed += 1
            # :requeued -> a transient failure; it re-leases on a later iteration
          end
        end
        Summary.new(completed: completed, failed: failed)
      end

      def drain_pool(pool: 4)
        summaries = []
        mutex = Mutex.new
        threads = Array.new(pool) do |i|
          Thread.new do
            s = drain(worker_id: "pool-#{Process.pid}-#{i}")
            mutex.synchronize { summaries << s }
          end
        end
        threads.each(&:join)
        Summary.new(
          completed: summaries.sum(&:completed),
          failed: summaries.sum(&:failed),
        )
      end

      private

      # Returns :completed on ack, or the queue's failure verdict (:requeued |
      # :dead_lettered) on a raise. A requeued job re-leases on the next loop
      # iteration, so a transient failure still drains; only a dead-letter is a
      # terminal failure that counts toward the summary.
      def run_one(leased)
        entry = @registry.lookup(leased.job.type)
        entry.handler.call(job: leased.job, container: @container)
        @queue.ack(leased)
        :completed
      rescue StandardError => e
        @queue.fail(leased, error: e.message)
      end
    end
  end
end
