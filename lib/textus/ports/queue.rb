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

      # A claimed job plus the path it lives at, so ack/fail act on this copy.
      Leased = Struct.new(:job, :leased_path, keyword_init: true)

      def lease(worker_id:, lease_ttl:)
        ready_dir = Textus::Layout.queue_state(@root, :ready)
        Dir.children(ready_dir).each do |name|
          src = File.join(ready_dir, name)
          dst = File.join(Textus::Layout.queue_state(@root, :leased), name)
          begin
            File.rename(src, dst) # atomic claim; loser's rename raises ENOENT
          rescue Errno::ENOENT
            next # another worker won this one
          end
          job = Textus::Domain::Jobs::Job.from_h(JSON.parse(File.read(dst)))
          stamp_lease(dst, worker_id: worker_id, expires_at: Time.now.utc + lease_ttl)
          return Leased.new(job: job, leased_path: dst)
        end
        nil
      end

      def ack(leased)
        dest = File.join(Textus::Layout.queue_state(@root, :done), File.basename(leased.leased_path))
        File.rename(leased.leased_path, dest)
      end

      # Increment attempts and either requeue (transient) or dead-letter (attempts
      # exhausted). Returns :requeued or :dead_lettered so the worker can count
      # terminal failures distinctly from retries.
      def fail(leased, error:)
        job = leased.job
        job.attempts += 1
        job.last_error = error
        dead = job.attempts >= job.max_attempts
        write_atomic(path(dead ? :failed : :ready, job.id), job.to_h)
        File.delete(leased.leased_path)
        dead ? :dead_lettered : :requeued
      end

      # Return expired leases to ready/ (the holding worker crashed). Returns the
      # count reclaimed. At-least-once delivery: a job whose handler actually
      # finished but whose ack was lost will re-run — handlers must be idempotent.
      def reclaim(now:)
        leased_dir = Textus::Layout.queue_state(@root, :leased)
        count = 0
        Dir.children(leased_dir).each do |name|
          src = File.join(leased_dir, name)
          data = JSON.parse(File.read(src))
          expires = data.dig("lease", "expires_at")
          next if expires && Time.parse(expires) > now

          dst = File.join(Textus::Layout.queue_state(@root, :ready), name)
          data.delete("lease")
          File.write(src, JSON.pretty_generate(data))
          File.rename(src, dst)
          count += 1
        rescue Errno::ENOENT
          next # raced with another reclaimer / the worker's ack
        end
        count
      end

      def list(state)
        Dir.children(Textus::Layout.queue_state(@root, state.to_sym)).map { |f| File.basename(f, ".json") }
      end

      def retry_failed(job_id)
        src = path(:failed, job_id)
        data = JSON.parse(File.read(src))
        data["attempts"] = 0
        data["last_error"] = nil
        write_atomic(path(:ready, job_id), data)
        File.delete(src)
      end

      def purge(state)
        dir = Textus::Layout.queue_state(@root, state.to_sym)
        Dir.children(dir).each { |f| File.delete(File.join(dir, f)) }
      end

      private

      def stamp_lease(leased_path, worker_id:, expires_at:)
        data = JSON.parse(File.read(leased_path))
        data["lease"] = { "worker_id" => worker_id, "expires_at" => expires_at.iso8601 }
        File.write(leased_path, JSON.pretty_generate(data))
      end

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
