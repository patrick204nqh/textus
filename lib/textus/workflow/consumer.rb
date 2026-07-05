module Textus
  module Workflow
    class Consumer
      BACKOFF_DELAYS = [10, 30, 60].freeze

      def initialize(registry:, container:, call:)
        @registry = registry
        @container = container
        @call = call
      end

      def consume(row, workflow_queue)
        workflow_queue.mark_processing(row[:id])
        workflow = @registry.for(row[:workflow_type])
        Runner.new(workflow, container: @container, call: @call).run(row[:key])
        workflow_queue.complete(row[:id])
        row.merge(state: "done")
      rescue StandardError => e
        handle_failure(row, workflow_queue, e)
      end

      private

      def handle_failure(row, workflow_queue, error)
        retry_count = (row[:retry_count] || 0) + 1
        max_attempts = row[:max_attempts] || 3

        if retry_count >= max_attempts
          workflow_queue.fail(row[:id], retry_count:, error: error.message)
          row.merge(state: "failed", error: error.message)
        else
          index = [retry_count - 1, BACKOFF_DELAYS.length - 1].min
          workflow_queue.reschedule(row[:id], retry_count:, delay: BACKOFF_DELAYS[index], error: error.message)
          row.merge(state: "retrying")
        end
      end
    end
  end
end
