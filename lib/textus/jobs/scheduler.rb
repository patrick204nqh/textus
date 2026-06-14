module Textus
  module Jobs
    # Time-based seeding for the daemon: at each tick, enqueue a re-pull job for
    # every intake key past its source.ttl and a sweep job to GC entries past
    # retention.ttl. Dedup means a job already queued from a prior tick is a
    # no-op. Both are stamped automation (the daemon's own authority); the sweep
    # handler runs retention as that role.
    class Scheduler
      def initialize(container:, queue:)
        @container = container
        @queue = queue
      end

      def run_once
        planner = Textus::Jobs::Planner.new(container: @container)
        jobs = planner.plan(
          triggers: [{ "type" => "schedule.tick" }],
          scope: { "prefix" => nil, "lane" => nil },
          role: Textus::Role::AUTOMATION,
        )
        jobs.each { |j| @queue.enqueue(j) }
      end
    end
  end
end
