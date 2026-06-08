module Textus
  module Maintenance
    # Converge-and-exit: seed the full convergence set for the scope, run the
    # worker until the queue is empty, return a health summary. Exits not-ok if
    # any job dead-lettered. This is what `reconcile` delegates to and what CI
    # runs. Single-pass (serial) on purpose: each produce job self-locks via
    # Produce::Engine.converge, so running them in turn keeps the build lock
    # uncontended; a concurrent pool would make all-but-one produce job hit
    # BuildInProgress and skip. Async produce-on-write threads are drained first
    # so their work folds in and the lock is free.
    class Drain
      extend Textus::Contract::DSL

      verb     :drain
      summary  "Converge everything now: seed produce + retention jobs and drain the queue to empty."
      surfaces :cli, :mcp
      cli      "drain"
      arg :prefix, String, description: "restrict convergence to keys under this dotted prefix"
      arg :zone,   String, description: "restrict convergence to entries in this zone"

      def initialize(container:, call:)
        @container = container
        @call = call
      end

      def call(prefix: nil, zone: nil)
        Textus::Produce::Engine::AsyncRunner.drain

        queue = Textus::Ports::Queue.new(root: @container.root)
        Textus::Jobs::Seeder.new(container: @container, queue: queue, call: @call).seed(prefix: prefix, zone: zone)

        summary = worker(queue).drain
        health = Read::Doctor.new(container: @container, call: @call).call

        {
          "protocol" => Textus::PROTOCOL,
          "ok" => summary.failed.zero?,
          "completed" => summary.completed,
          "failed" => summary.failed,
          "health" => health,
        }
      end

      private

      def worker(queue)
        Textus::Maintenance::Worker.new(
          queue: queue, registry: Textus::Jobs::Handlers.registry,
          container: @container, lease_ttl: @container.manifest.data.worker_config[:lease_ttl]
        )
      end
    end
  end
end
