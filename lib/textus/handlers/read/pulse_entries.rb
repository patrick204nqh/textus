module Textus
  module Handlers
    module Read
      class PulseEntries
        def initialize(manifest:, audit_log:, file_store:, orchestration:, job_store: nil)
          @manifest = manifest
          @audit_log = audit_log
          @file_store = file_store
          @orchestration = orchestration
          @job_store = job_store
        end

        def call(command, call)
          root  = @manifest.data.root
          since = command.since || Textus::Store::Cursor.new(root: root, role: call.role).read

          changed = changed_since(since, call)

          result = {
            "cursor" => @audit_log.latest_seq,
            "changed" => changed,
            "pending_review" => review_keys(call),
            "contract_etag" => Textus::Value::Etag.for_contract(root),
            "index_etag" => index_etag,
          }

          Textus::Store::Cursor.new(root: root, role: call.role).write(result["cursor"])
          Value::Result.success(result)
        end

        private

        def changed_since(since, call)
          if @job_store
            sqlite_rows = @job_store.audit_events_since(seq: since)
            return sqlite_rows.map { |r| { "key" => r["key"], "verb" => r["verb"], "seq" => r["seq"] } } if sqlite_rows.any?
          end

          # Fall back to flat-log scan when SQLite index is empty for this window
          # (writes that bypassed dispatch, fresh stores, or pre-migration entries).
          audit = @orchestration.audit_entries(seq_since: since, call: call)
          return [] if audit.failure?

          audit.value.fetch("rows") || []
        end

        def review_keys(call)
          queue = @manifest.policy.queue_lane
          return [] unless queue

          result = @orchestration.list_keys(prefix: nil, lane: queue, call: call)
          return [] unless result.success?

          result.value.fetch("rows").map { |r| r["key"] }
        end

        def index_etag
          path = @manifest.resolver.resolve("artifacts.system.index").path
          File.exist?(path) ? @file_store.etag(path) : nil
        rescue Textus::Error
          nil
        end
      end
    end
  end
end
