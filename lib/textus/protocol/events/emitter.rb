module Textus
  module Protocol
    module Events
      class Emitter
        def initialize(workflow_queue:, workflow_registry:)
          @workflow_queue = workflow_queue
          @registry = workflow_registry
        end

        def emit(event_type:, key: nil, lane: nil, payload: {})
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
      end
    end
  end
end
