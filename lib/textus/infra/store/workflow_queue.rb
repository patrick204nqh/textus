module Textus
  module Infra
    class Store
      class WorkflowQueue < Base
        def push(event_type:, workflow_type:, key:, lane:, payload: nil,
                 created_at: Time.now.utc, scheduled_at: nil,
                 state: "pending", retry_count: 0, max_attempts: 3)
          table(:workflow_events).insert(
            event_type: event_type.to_s, workflow_type:, key:, lane:,
            payload: payload&.to_json, created_at:, scheduled_at:,
            state:, retry_count:, max_attempts:
          )
        end

        def pop
          row = table(:workflow_events)
                .where(state: "pending")
                .where(Sequel.|({ scheduled_at: nil }, Sequel.lit("scheduled_at <= datetime('now')")))
                .order(:created_at, :id)
                .limit(1)
                .for_update
                .first
          result(row)
        end

        def complete(event_id)
          table(:workflow_events).where(id: event_id).update(state: "done")
        end

        def fail(event_id, retry_count:, error:)
          table(:workflow_events).where(id: event_id).update(state: "failed", retry_count:, error:)
        end

        def reschedule(event_id, retry_count:, delay:, error:)
          table(:workflow_events).where(id: event_id).update(
            state: "pending", retry_count:, error:,
            scheduled_at: Sequel.lit("datetime('now', '+#{delay.to_i} seconds')")
          )
        end
      end
    end
  end
end
