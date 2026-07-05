module Textus
  module Workflow
    class EventEmitter
      def initialize(workflow_queue, registry:)
        @workflow_queue = workflow_queue
        @registry = registry
      end

      def emit(event_type:, key:, lane: "artifacts")
        workflows = @registry.workflows_for(event_type)
        workflows.each do |wf|
          @workflow_queue.push(
            event_type: event_type.to_s, workflow_type: wf.type,
            key:, lane:, max_attempts: wf.max_attempts,
          )
        end
        workflows.size
      end
    end
  end
end
