require "json"
require "time"

module Textus
  module Infra
    class Store
      class EventStore
        def initialize(database)
          @db = database
        end

        # ── Audit ──

        def append_audit(role:, verb:, key:, etag_before:, etag_after:, correlation_id: nil)
          @db[:audit_events].insert(
            ts: Time.now.utc.iso8601,
            role:, verb:, key:,
            etag_before:, etag_after:, correlation_id:
          )
        end

        def scan_audit(seq_since: nil, key: nil, role: nil, verb: nil, correlation_id: nil, limit: nil)
          dataset = @db[:audit_events]
          dataset = dataset.where { seq > seq_since } if seq_since
          dataset = dataset.where(key:) if key
          dataset = dataset.where(role:) if role
          dataset = dataset.where(verb:) if verb
          dataset = dataset.where(correlation_id:) if correlation_id
          dataset = dataset.limit(limit) if limit
          dataset.order(:seq).all.map { |row| row.transform_keys(&:to_s) }
        end
        alias scan scan_audit

        def latest_seq
          row = @db[:audit_events].order(Sequel.desc(:seq)).first
          row ? row[:seq] : 0
        end

        def min_available_seq
          row = @db[:audit_events].order(:seq).first
          row ? row[:seq] : nil
        end

        def last_writer_for(key)
          row = @db[:audit_events]
                .where(key:, verb: %w[put delete key_delete])
                .order(Sequel.desc(:seq))
                .first
          row ? row[:role] : nil
        end

        # ── Workflow ──

        def emit(event_type:, workflow_type:, key:, lane:, payload:,
                 created_at: Time.now.utc, scheduled_at: nil,
                 state: "pending", retry_count: 0, max_attempts: 3)
          @db[:workflow_events].insert(
            event_type: event_type.to_s, workflow_type:, key:, lane:,
            payload: payload.to_json, created_at:, scheduled_at:,
            state:, retry_count:, max_attempts:
          )
        end

        def consume_pending
          @db[:workflow_events]
            .where(state: "pending")
            .where(Sequel.|({ scheduled_at: nil }, Sequel.lit("scheduled_at <= datetime('now')")))
            .order(:created_at, :id)
            .limit(1)
            .first
        end

        def mark_done(event_id:) = @db[:workflow_events].where(id: event_id).update(state: "done")

        def mark_failed(event_id:, retry_count:, error:)
          @db[:workflow_events].where(id: event_id).update(state: "failed", retry_count:, error:)
        end

        def reschedule(event_id:, retry_count:, delay:, error:)
          @db[:workflow_events].where(id: event_id).update(
            state: "pending", retry_count:, error:,
            scheduled_at: Sequel.lit("datetime('now', '+#{delay.to_i} seconds')")
          )
        end
      end
    end
  end
end
