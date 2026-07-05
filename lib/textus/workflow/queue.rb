module Textus
  module Workflow
    class Queue
      def initialize(workflow_queue, registry:, container:, call:)
        @workflow_queue = workflow_queue
        @consumer = Consumer.new(registry:, container:, call:)
        @registry = registry
      end

      def enqueue(event_type:, key:, lane:, payload: nil)
        workflows = @registry.workflows_for(event_type)
        return 0 if workflows.empty?

        workflows.each do |wf|
          @workflow_queue.push(
            event_type: event_type.to_s, workflow_type: wf.type,
            key:, lane:, payload:,
            max_attempts: wf.max_attempts
          )
        end
        workflows.size
      end

      def consume_one
        row = @workflow_queue.pop
        return nil unless row

        @consumer.consume(row, @workflow_queue)
      end

      def drain
        completed = 0
        failed = 0

        loop do
          row = @workflow_queue.pop
          break unless row

          result = @consumer.consume(row, @workflow_queue)
          if result[:state] == "done"
            completed += 1
          else
            failed += 1
          end
        end

        { completed:, failed: }
      end
    end
  end
end
