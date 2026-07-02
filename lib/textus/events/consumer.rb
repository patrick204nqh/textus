# frozen_string_literal: true

module Textus
  module Events
    class Consumer
      BACKOFF_DELAYS = [10, 30, 60].freeze

      def drain(database:, registry:, container:, call:)
        completed = 0
        failed = 0

        loop do
          row = consume_one(database, registry, container, call)
          break unless row

          if row[:state] == "done"
            completed += 1
          elsif row[:state] == "failed"
            failed += 1
          end
        end

        { completed: completed, failed: failed }
      end

      def consume_one(database, registry, container, call)
        row = database[:events]
              .where(state: "pending")
              .where(Sequel.|({ scheduled_at: nil }, Sequel.lit("scheduled_at <= datetime('now')")))
              .order(:created_at, :id)
              .limit(1)
              .first
        return nil unless row

        workflow = registry.for(row[:workflow_type])
        Textus::Workflow::Runner.new(workflow, container: container, call: call).run(row[:key])
        db[:events].where(id: row[:id]).update(state: "done")
        row.merge(state: "done")
      rescue StandardError => e
        retry_count = (row[:retry_count] || 0) + 1
        max_attempts = row[:max_attempts] || 3

        if retry_count >= max_attempts
          db[:events].where(id: row[:id]).update(
            state: "failed", retry_count: retry_count, error: e.message,
          )
          row.merge(state: "failed", error: e.message)
        else
          delay = BACKOFF_DELAYS[[retry_count - 1, BACKOFF_DELAYS.length - 1].min]
          db[:events].where(id: row[:id]).update(
            state: "pending", retry_count: retry_count,
            scheduled_at: (Time.now.utc + delay).iso8601,
            error: e.message
          )
          row.merge(state: "retrying")
        end
      end
    end
  end
end
