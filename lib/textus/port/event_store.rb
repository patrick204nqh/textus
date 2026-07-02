module Textus
  module Port
    class EventStore
      module Interface
        def emit(event_type:, workflow_type:, key:, lane:, payload:, **) = raise NotImplementedError
        def consume_pending = raise NotImplementedError
        def mark_done(id:) = raise NotImplementedError
        def mark_failed(id:, retry_count:, error:) = raise NotImplementedError
        def reschedule(id:, retry_count:, delay:, error:) = raise NotImplementedError
        def search_entries(q:, schema:, lane:, prefix:) = raise NotImplementedError
      end
      include Interface
    end
  end
end
