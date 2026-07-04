module Textus
  module Protocol
    module Async
      class Queue
        def initialize(workflow_queue, retry_policy: Events::RetryPolicy.new)
          @workflow_queue = workflow_queue
          @retry_policy = retry_policy
        end

        def enqueue(workflow_type, key, lane:, payload: nil, scheduled_at: nil)
          @workflow_queue.push(
            event_type: "workflow", workflow_type:,
            key:, lane:,
            payload: payload,
            scheduled_at: scheduled_at || Time.now.utc
          )
        end

        def consume_one(registry:, container:, call:)
          row = @workflow_queue.pop
          return nil unless row

          workflow = registry.for(row[:workflow_type])
          Textus::Workflow::Runner.new(workflow, container:, call:).run(row[:key])
          @workflow_queue.complete(row[:id])
          row.merge(state: "done")
        rescue StandardError => e
          handle_failure(row, e)
        end

        private

        def handle_failure(row, error)
          retry_count = (row[:retry_count] || 0) + 1
          max_attempts = row[:max_attempts] || 3
          decision = @retry_policy.decide(retry_count:, max_attempts:)

          if decision.terminal?
            @workflow_queue.fail(row[:id], retry_count:, error: error.message)
            row.merge(state: "failed", error: error.message)
          else
            @workflow_queue.reschedule(row[:id], retry_count:, delay: decision.delay, error: error.message)
            row.merge(state: "retrying")
          end
        end
      end
    end
  end
end
