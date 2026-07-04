module Textus
  module Protocol
    module Events
      class Emitter
        def initialize(event_store:, workflow_registry:)
          @event_store = event_store
          @registry = workflow_registry
        end

        def emit(event_type:, key: nil, lane: nil, payload: {})
          workflows = @registry.workflows_for(event_type)
          return 0 if workflows.empty?

          workflows.each do |wf|
            @event_store.emit(
              event_type: event_type.to_s, workflow_type: wf.type,
              key: key, lane: lane, payload: payload,
              max_attempts: wf.max_attempts
            )
          end
          workflows.size
        end
      end
    end
  end
end
