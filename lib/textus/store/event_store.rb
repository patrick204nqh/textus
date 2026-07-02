module Textus
  class Store
    class EventStore
      include Port::EventStore::Interface

      def initialize(database)
        @db = database.connection
      end

      def connection = @db
      alias_method :db, :connection

      def emit(event_type:, workflow_type:, key:, lane:, payload:,
               created_at: Time.now.utc, scheduled_at: nil,
               state: "pending", retry_count: 0, max_attempts: 3)
        @db[:events].insert(
          event_type: event_type.to_s, workflow_type:, key:, lane:,
          payload: payload.to_json, created_at:, scheduled_at:,
          state:, retry_count:, max_attempts:
        )
      end

      def consume_pending
        @db[:events]
          .where(state: "pending")
          .where(Sequel.|({ scheduled_at: nil }, Sequel.lit("scheduled_at <= datetime('now')")))
          .order(:created_at, :id)
          .limit(1)
          .first
      end

      def mark_done(id:)   = @db[:events].where(id:).update(state: "done")
      def mark_failed(id:, retry_count:, error:)
        @db[:events].where(id:).update(state: "failed", retry_count:, error:)
      end

      def reschedule(id:, retry_count:, delay:, error:)
        @db[:events].where(id:).update(
          state: "pending", retry_count:, error:,
          scheduled_at: Sequel.lit("datetime('now', '+#{delay.to_i} seconds')")
        )
      end

      def search_entries(q:, schema:, lane:, prefix:)
        query = @db[:entries]
        query = query.where(Sequel.lit("entries MATCH ?", q)) if q
        query = query.where(schema:) if schema
        query = query.where(lane:) if lane
        query = query.where(Sequel.like(:key, "#{prefix}%")) if prefix
        query.all
      end
    end
  end
end
