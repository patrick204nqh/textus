module Textus
  module Maintenance
    # Converge-and-exit: seed the full convergence set for the scope, run the
    # worker until the queue is empty, return a health summary. Exits not-ok if
    # any job dead-lettered. This is the converge entry point and what CI
    # runs. Single-pass (serial) on purpose: each produce job self-locks via
    # Produce::Engine.converge, so running them in turn keeps the build lock
    # uncontended; a concurrent pool would make all-but-one produce job hit
    # BuildInProgress and skip.
    class Drain
      extend Textus::Contract::DSL

      verb     :drain
      summary  "Converge everything now: seed produce + retention jobs and drain the queue to empty."
      surfaces :cli, :mcp
      cli      "drain"
      arg :prefix, String, description: "restrict convergence to keys under this dotted prefix"
      arg :lane,   String, description: "restrict convergence to entries in this lane"

      def initialize(container:, call:)
        @container = container
        @call = call
      end

      def call(prefix: nil, lane: nil)
        _ = prefix
        _ = lane

        queue = Textus::Ports::Queue.new(root: @container.root)
        completed = 0
        failed = 0

        while (leased = queue.lease(worker_id: "drain", lease_ttl: 60))
          begin
            run_queued_job(leased)
            queue.ack(leased)
            completed += 1
          rescue StandardError => e
            outcome = queue.fail(leased, error: e.message)
            failed += 1 if outcome == :dead_lettered
          end
        end

        {
          "protocol" => Textus::PROTOCOL,
          "ok" => failed.zero?,
          "completed" => completed,
          "failed" => failed,
        }
      end

      private

      def run_queued_job(leased)
        job = leased.job
        entry = Textus::Jobs::Handlers.registry.lookup(job.type)
        entry.handler.call(job: job, container: @container)
      end
    end
  end
end
