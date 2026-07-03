module Textus
  module Protocol
    module Async
      class Queue
        def initialize(event_store)
          @event_store = event_store
        end

        def enqueue(workflow_type, key, lane:, payload: nil, scheduled_at: nil)
          @event_store.emit(
            event_type: "workflow", workflow_type:,
            key:, lane:,
            payload: payload&.to_json,
            scheduled_at: scheduled_at || Time.now.utc
          )
        end

        def consume_pending = @event_store.consume_pending
        def mark_done(event_id:) = @event_store.mark_done(event_id:)
        def mark_failed(event_id:, retry_count:, error:) = @event_store.mark_failed(event_id:, retry_count:, error:)
      end
    end
  end
end
