module Textus
  module UseCases
    module Read
      class PulseEntries < Base
        handles Dispatch::Contracts::PulseEntries
        needs :file_system, :manifest, :audit_log, :event_store, :entry_index

        def call
          root  = @manifest.data.root
          since = @command.since || Textus::Store::Cursor.new(root: root, role: @call.role).read

          changed = changed_since(since)

          result = {
            "cursor" => @audit_log.latest_seq,
            "changed" => changed,
            "pending_review" => review_keys,
            "contract_etag" => Textus::Value::Etag.for_contract(root),
            "index_etag" => index_etag,
          }

          trace_buffer = @call.respond_to?(:trace_buffer) ? @call.trace_buffer : nil
          if trace_buffer
            result["trace_stats"] = trace_buffer.stats
            result["recent_traces"] = trace_buffer.recent(limit: 10).map(&:to_h_for_wire)
          end

          Textus::Store::Cursor.new(root: root, role: @call.role).write(result["cursor"])
          success(result)
        end

        private

        def deps_for_audit
          @deps_for_audit ||= Data.define(:manifest, :audit_log).new(manifest: @manifest, audit_log: @audit_log)
        end

        def deps_for_list
          @deps_for_list ||= Data.define(:manifest, :entry_index, :file_system, :layout).new(
            manifest: @manifest, entry_index: @entry_index, file_system: @file_system, layout: nil,
          )
        end

        def changed_since(since)
          audit = AuditEntries.call(
            Data.define(:seq_since, :key, :lane, :role, :verb, :since, :correlation_id, :limit).new(
              seq_since: since, key: nil, lane: nil, role: nil, verb: nil, since: nil, correlation_id: nil, limit: nil,
            ),
            @call,
            deps_for_audit,
          )
          return [] if audit.failure?

          audit.value || []
        end

        def review_keys
          queue = @manifest.policy.queue_lane
          return [] unless queue

          result = ListKeys.call(
            Data.define(:prefix, :lane, :q, :schema).new(
              prefix: nil, lane: queue, q: nil, schema: nil,
            ),
            @call,
            deps_for_list,
          )
          return [] unless result.success?

          result.value.map { |r| r["key"] }
        end

        def index_etag
          path = @manifest.resolver.resolve("artifacts.system.index").path
          File.exist?(path) ? @file_system.etag(path) : nil
        rescue Textus::Error
          nil
        end
      end
    end
  end
end
