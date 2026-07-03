module Textus
  module Port
    class EventStore
      module Interface
        def emit(event_type:, workflow_type:, key:, lane:, payload:, **) = raise NotImplementedError
        def consume_pending = raise NotImplementedError
        def mark_done(event_id:) = raise NotImplementedError
        def mark_failed(event_id:, retry_count:, error:) = raise NotImplementedError
        def reschedule(event_id:, retry_count:, delay:, error:) = raise NotImplementedError
      end
      include Interface
    end
  end
end
