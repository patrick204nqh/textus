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
        stale_intake.each do |key|
          @queue.enqueue(job("re-pull", { "key" => key }))
        end
        @queue.enqueue(job("sweep", { "scope" => { "prefix" => nil, "zone" => nil } }))
      end

      private

      def stale_intake
        Textus::Domain::Freshness::Evaluator.new(
          manifest: @container.manifest,
          file_stat: Textus::Ports::Storage::FileStat.new,
          clock: Textus::Ports::Clock.new,
        ).stale_intake_keys(prefix: nil, zone: nil)
      end

      def job(type, args)
        Textus::Domain::Jobs::Job.new(type: type, args: args, enqueued_by: Textus::Role::AUTOMATION)
      end
    end
  end
end
