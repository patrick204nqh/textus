module Textus
  module Workflow
    class EventEmitter
      def initialize(workflow_queue, registry:)
        @workflow_queue = workflow_queue
        @registry = registry
      end

      def emit(event_type:, key:, lane: "artifacts")
        count = 0

        @registry.workflows_for(event_type).each do |wf|
          push(wf, event_type, key, lane)
          count += 1
        end

        queued = @registry.workflows_for(event_type).map(&:type).to_set
        @registry.workflows_for_key(key).each do |wf|
          next if queued.include?(wf.type)
          push(wf, event_type, key, lane)
          count += 1
        end

        count
      end

      private

      def push(wf, event_type, key, lane)
        @workflow_queue.push(
          event_type: event_type.to_s, workflow_type: wf.type,
          key:, lane:, max_attempts: wf.max_attempts
        )
      end
    end
  end
end
