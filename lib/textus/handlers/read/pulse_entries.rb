module Textus
  module Handlers
    module Read
      module PulseEntries
        HANDLES = Dispatch::Contracts::PulseEntries
        NEEDS   = %i[manifest audit_log file_store orchestration job_store].freeze

        def self.call(command, call, deps)
          root  = deps.manifest.data.root
          since = command.since || Textus::Store::Cursor.new(root: root, role: call.role).read

          changed = changed_since(since, call, deps)

          result = {
            "cursor" => deps.audit_log.latest_seq,
            "changed" => changed,
            "pending_review" => review_keys(call, deps),
            "contract_etag" => Textus::Value::Etag.for_contract(root),
            "index_etag" => index_etag(deps),
          }

          Textus::Store::Cursor.new(root: root, role: call.role).write(result["cursor"])
          Value::Result.success(result)
        end

        def self.changed_since(since, call, deps)
          if deps.job_store
            sqlite_rows = deps.job_store.audit_events_since(seq: since)
            return sqlite_rows.map { |r| { "key" => r["key"], "verb" => r["verb"], "seq" => r["seq"] } } if sqlite_rows.any?
          end

          audit = deps.orchestration.audit_entries(seq_since: since, call: call)
          return [] if audit.failure?

          audit.value.fetch("rows") || []
        end

        def self.review_keys(call, deps)
          queue = deps.manifest.policy.queue_lane
          return [] unless queue

          result = deps.orchestration.list_keys(prefix: nil, lane: queue, call: call)
          return [] unless result.success?

          result.value.fetch("rows").map { |r| r["key"] }
        end

        def self.index_etag(deps)
          path = deps.manifest.resolver.resolve("artifacts.system.index").path
          File.exist?(path) ? deps.file_store.etag(path) : nil
        rescue Textus::Error
          nil
        end
      end
    end
  end
end
