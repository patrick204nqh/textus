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
      arg :zone,   String, description: "restrict convergence to entries in this zone"

      def initialize(container:, call:)
        @container = container
        @call = call
      end

      def call(prefix: nil, zone: nil)
        queue = Textus::Ports::Queue.new(root: @container.root)
        Textus::Jobs::Seeder.new(container: @container, queue: queue, call: @call).seed(prefix: prefix, zone: zone)

        summary = Worker.for(container: @container, queue: queue).drain
        health = Read::Doctor.new(container: @container, call: @call).call

        {
          "protocol" => Textus::PROTOCOL,
          "ok" => summary.failed.zero?,
          "completed" => summary.completed,
          "failed" => summary.failed,
          "health" => health,
        }
      end
    end
  end
end
