module Textus
  module Protocol
    module Events
      class Consumer
        def initialize(retry_policy: Textus::Protocol::Events::RetryPolicy.new)
          @retry_policy = retry_policy
        end

        def drain(event_store:, registry:, container:, call:)
          completed = 0
          failed = 0

          loop do
            row = consume_one(event_store:, registry:, container:, call:)
            break unless row

            if row[:state] == "done"
              completed += 1
            elsif row[:state] == "failed"
              failed += 1
            end
          end

          { completed: completed, failed: failed }
        end

        def consume_one(event_store:, registry:, container:, call:)
          row = event_store.consume_pending
          return nil unless row

          workflow = registry.for(row[:workflow_type])
          Textus::Workflow::Runner.new(workflow, container: container, call: call).run(row[:key])
          event_store.mark_done(event_id: row[:id])
          row.merge(state: "done")
        rescue StandardError => e
          handle_failure(event_store, row, e)
        end

        private

        def handle_failure(event_store, row, error)
          retry_count = (row[:retry_count] || 0) + 1
          max_attempts = row[:max_attempts] || 3
          decision = @retry_policy.decide(retry_count:, max_attempts:)

          if decision.terminal?
            event_store.mark_failed(event_id: row[:id], retry_count:, error: error.message)
            row.merge(state: "failed", error: error.message)
          else
            event_store.reschedule(event_id: row[:id], retry_count:, delay: decision.delay, error: error.message)
            row.merge(state: "retrying")
          end
        end
      end
    end
  end
end
