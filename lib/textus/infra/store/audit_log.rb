module Textus
  module Infra
    class Store
      class AuditLog < Base
        def append(role:, verb:, key:, etag_before: nil, etag_after: nil, correlation_id: nil)
          table(:audit_events).insert(
            ts: Time.now.utc.iso8601,
            role:, verb:, key:,
            etag_before:, etag_after:, correlation_id:
          )
        end

        def list(seq_since: nil, key: nil, role: nil, verb: nil, correlation_id: nil, limit: nil)
          dataset = table(:audit_events)
          dataset = dataset.where { seq > seq_since } if seq_since
          dataset = dataset.where(key:) if key
          dataset = dataset.where(role:) if role
          dataset = dataset.where(verb:) if verb
          dataset = dataset.where(correlation_id:) if correlation_id
          dataset = dataset.limit(limit) if limit
          results(dataset.order(:seq).all)
        end

        def latest
          result(table(:audit_events).order(Sequel.desc(:seq)).first) || { seq: 0 }
        end

        def min_available
          result(table(:audit_events).order(:seq).first)&.dig(:seq)
        end

        def last_writer(key)
          row = table(:audit_events)
                .where(key:, verb: %w[put delete key_delete])
                .order(Sequel.desc(:seq))
                .first
          result(row)
        end
      end
    end
  end
end
