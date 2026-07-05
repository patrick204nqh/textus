module Textus
  module Workflow
    class Queue
      def initialize(workflow_queue, registry:, container:, call:)
        @workflow_queue = workflow_queue
        @registry = registry
        @container = container
        @call = call
        @retry_policy = RetryPolicy.new
      end

      def enqueue(event_type:, key:, lane:, payload: nil)
        workflows = @registry.workflows_for(event_type)
        return 0 if workflows.empty?

        workflows.each do |wf|
          @workflow_queue.push(
            event_type: event_type.to_s, workflow_type: wf.type,
            key:, lane:, payload:,
            max_attempts: wf.max_attempts,
          )
        end
        workflows.size
      end

      def drain
        completed = 0
        failed = 0

        loop do
          row = @workflow_queue.pop
          break unless row

          @workflow_queue.mark_processing(row[:id])
          execute(row)
          @workflow_queue.complete(row[:id])
          completed += 1
        rescue StandardError => e
          handle_failure(row, e)
          failed += 1
        end

        { completed:, failed: }
      end

      private

      def execute(row)
        workflow = @registry.for(row[:workflow_type])
        Runner.new(workflow, container: @container, call: @call).run(row[:key])
      end

      def handle_failure(row, error)
        retry_count = (row[:retry_count] || 0) + 1
        max_attempts = row[:max_attempts] || 3
        decision = @retry_policy.decide(retry_count:, max_attempts:)

        if decision.terminal?
          @workflow_queue.fail(row[:id], retry_count:, error: error.message)
        else
          @workflow_queue.reschedule(row[:id], retry_count:, delay: decision.delay, error: error.message)
        end
      end
    end
  end
end
