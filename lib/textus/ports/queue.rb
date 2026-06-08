require "fileutils"
require "json"
require "time"

module Textus
  module Ports
    # File-backed durable job queue under `<root>/.run/queue/`. Each job state
    # is a directory; a job is one `<id>.json` file. Claiming is an atomic
    # `rename(2)` from ready/ to leased/ — the rename winner owns the job, so a
    # worker pool needs no central lock. Dedup falls out of the id-as-filename:
    # enqueueing an id that already exists is a no-op. ADR 0038 (runtime subtree),
    # ADR 0108 (instantiable port).
    class Queue
      STATES = %i[ready leased done failed].freeze

      def initialize(root:)
        @root = root
        STATES.each { |s| FileUtils.mkdir_p(Textus::Layout.queue_state(root, s)) }
      end

      def enqueue(job)
        dest = path(:ready, job.id)
        return if File.exist?(dest) # dedup: identical work already queued

        write_atomic(dest, job.to_h)
      end

      def ready_ids
        Dir.children(Textus::Layout.queue_state(@root, :ready)).map { |f| File.basename(f, ".json") }
      end

      private

      def path(state, job_id)
        File.join(Textus::Layout.queue_state(@root, state), "#{job_id}.json")
      end

      def write_atomic(dest, hash)
        tmp = "#{dest}.#{Process.pid}.tmp"
        File.write(tmp, JSON.pretty_generate(hash))
        File.rename(tmp, dest) # atomic on same filesystem
      end
    end
  end
end
