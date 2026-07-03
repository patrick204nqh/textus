module Textus
  module Infra
  class Store
    class EventStore
      include Textus::Infra::Port::Storage::EventStore::Interface

      def initialize(database)
        @db = database.connection
      end

      def connection = @db
      alias db connection

      # rubocop:disable Metrics/ParameterLists
      def emit(event_type:, workflow_type:, key:, lane:, payload:,
               created_at: Time.now.utc, scheduled_at: nil,
               state: "pending", retry_count: 0, max_attempts: 3)
        @db[:events].insert(
          event_type: event_type.to_s, workflow_type:, key:, lane:,
          payload: payload.to_json, created_at:, scheduled_at:,
          state:, retry_count:, max_attempts:
        )
      end
      # rubocop:enable Metrics/ParameterLists

      def consume_pending
        @db[:events]
          .where(state: "pending")
          .where(Sequel.|({ scheduled_at: nil }, Sequel.lit("scheduled_at <= datetime('now')")))
          .order(:created_at, :id)
          .limit(1)
          .first
      end

      def mark_done(event_id:)   = @db[:events].where(id: event_id).update(state: "done")

      def mark_failed(event_id:, retry_count:, error:)
        @db[:events].where(id: event_id).update(state: "failed", retry_count:, error:)
      end

      def reschedule(event_id:, retry_count:, delay:, error:)
        @db[:events].where(id: event_id).update(
          state: "pending", retry_count:, error:,
          scheduled_at: Sequel.lit("datetime('now', '+#{delay.to_i} seconds')")
        )
      end
    end
  end
  end
end
