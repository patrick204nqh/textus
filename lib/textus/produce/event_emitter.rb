# frozen_string_literal: true

module Textus
  module Produce
    class EventEmitter
      def initialize(db:, workflow_registry:)
        @db = db
        @registry = workflow_registry
      end

      def emit(event_type:, key: nil, lane: nil, payload: {})
        workflows = @registry.workflows_for(event_type)
        return 0 if workflows.empty?

        now = Time.now.utc
        rows = workflows.map do |wf|
          {
            event_type: event_type.to_s,
            workflow_type: wf.type,
            key: key,
            lane: lane,
            payload: payload.to_json,
            created_at: now,
            state: "pending",
            retry_count: 0,
            max_attempts: wf.max_attempts,
          }
        end

        @db[:events].multi_insert(rows)
        rows.size
      end
    end
  end
end
