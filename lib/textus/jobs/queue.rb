# frozen_string_literal: true

require "digest"
require "json"
require "securerandom"
require "time"

module Textus
  module Jobs
    class Queue
      VALID_STATES = %w[ready leased done failed].freeze

      Leased = Data.define(:job)

      class Job
        DIGEST_BYTES = 16

        attr_reader :type, :args, :role, :attempts, :max_attempts, :errors

        def initialize(type:, args:, role:, attempts: 0, max_attempts: 3, errors: [])
          @type = type.to_s
          @args = stringify(args)
          @role = role.to_s
          @attempts = attempts.to_i
          @max_attempts = max_attempts.to_i
          @errors = Array(errors)
        end

        def id
          "#{type}:#{Digest::SHA256.hexdigest(JSON.dump(args.sort.to_h))[0, DIGEST_BYTES]}"
        end

        private

        def stringify(hash)
          hash.to_h.transform_keys(&:to_s)
        end
      end

      def initialize(store:)
        @store = store
        @db = store.connection
      end

      def enqueue(job)
        now = iso_now
        @db.execute(
          "INSERT OR IGNORE INTO jobs (id, type, args, state, role, attempts, max_attempts, errors, lease, created_at, updated_at)
           VALUES (?, ?, ?, 'ready', ?, ?, ?, ?, NULL, ?, ?)",
          [job.id, job.type, JSON.dump(job.args), job.role, job.attempts, job.max_attempts, JSON.dump(job.errors), now, now],
        )
      end

      def ready_ids
        list(:ready)
      end

      def lease(worker_id:, lease_ttl:)
        now = Time.now.utc
        expires_at = now + lease_ttl
        token = SecureRandom.hex(8)
        marked_lease = JSON.dump({ "worker_id" => worker_id, "expires_at" => expires_at.iso8601, "token" => token })

        @db.execute(
          "UPDATE jobs
              SET state = 'leased', lease = ?, updated_at = ?
            WHERE id = (
              SELECT id FROM jobs WHERE state = 'ready' ORDER BY created_at, id LIMIT 1
            )",
          [marked_lease, now.iso8601],
        )
        row = @db.get_first_row("SELECT * FROM jobs WHERE state = 'leased' AND lease = ? LIMIT 1", [marked_lease])
        return nil unless row

        Leased.new(job_from_row(row))
      end

      def ack(leased)
        @db.execute(
          "UPDATE jobs SET state = 'done', lease = NULL, updated_at = ? WHERE id = ? AND state = 'leased'",
          [iso_now, leased.job.id],
        )
      end

      def fail(leased, error:)
        job = leased.job
        attempts = job.attempts + 1
        errors = job.errors + [{ "attempt" => attempts, "error" => error, "at" => iso_now }]
        dead = attempts >= job.max_attempts
        state = dead ? "failed" : "ready"
        @db.execute(
          "UPDATE jobs SET state = ?, attempts = ?, errors = ?, lease = NULL, updated_at = ? WHERE id = ?",
          [state, attempts, JSON.dump(errors), iso_now, job.id],
        )
        dead ? :dead_lettered : :requeued
      end

      def reclaim(now:)
        rows = @db.execute("SELECT id, lease FROM jobs WHERE state = 'leased'")
        expired = rows.select do |row|
          lease = JSON.parse(row["lease"] || "{}")
          expires_at = lease["expires_at"]
          expires_at.nil? || Time.parse(expires_at) <= now
        end
        expired.each do |row|
          @db.execute(
            "UPDATE jobs SET state = 'ready', lease = NULL, updated_at = ? WHERE id = ?",
            [now.utc.iso8601, row["id"]],
          )
        end
        expired.size
      end

      def list(state)
        state = state.to_s
        raise Textus::UsageError.new("unknown job state: #{state}") unless VALID_STATES.include?(state)

        @db.execute("SELECT id FROM jobs WHERE state = ? ORDER BY created_at, id", [state]).map { |row| row["id"] }
      end

      def retry_failed(job_id)
        @db.execute(
          "UPDATE jobs SET state = 'ready', attempts = 0, errors = ?, lease = NULL, updated_at = ? WHERE id = ? AND state = 'failed'",
          [JSON.dump([]), iso_now, job_id],
        )
      end

      def purge(state)
        state = state.to_s
        raise Textus::UsageError.new("unknown job state: #{state}") unless VALID_STATES.include?(state)

        @db.execute("DELETE FROM jobs WHERE state = ?", [state])
      end

      private

      def job_from_row(row)
        Job.new(
          type: row["type"],
          args: JSON.parse(row["args"] || "{}"),
          role: row["role"],
          attempts: row["attempts"],
          max_attempts: row["max_attempts"],
          errors: JSON.parse(row["errors"] || "[]"),
        )
      end

      def iso_now
        Time.now.utc.iso8601
      end
    end
  end
end
