module Textus
  module Handlers
    class PulseEntries
      AuditQuery = Struct.new(:seq_since, :key, :lane, :role, :verb, :since, :correlation_id, :limit, keyword_init: true)
      ListQuery = Struct.new(:prefix, :lane, keyword_init: true)

      def initialize(container:, manifest:, audit_log:, file_store:)
        @container = container
        @manifest = manifest
        @audit_log = audit_log
        @file_store = file_store
      end

      def call(command, call)
        root = @manifest.data.root
        since = command.since || Textus::Store::Cursor.new(root: root, role: call.role).read

        audit_handler = Handlers::AuditEntries.new(manifest: @manifest, audit_log: @audit_log)
        audit_result = audit_handler.call(AuditQuery.new(seq_since: since), call)
        return audit_result unless audit_result.success?

        changed = audit_result.value

        result = {
          "cursor" => @audit_log.latest_seq,
          "changed" => changed || [],
          "pending_review" => review_keys(call),
          "contract_etag" => Textus::Value::Etag.for_contract(root),
          "index_etag" => index_etag,
        }

        Textus::Store::Cursor.new(root: root, role: call.role).write(result["cursor"])
        Result.success(result)
      end

      private

      def review_keys(call)
        queue = @manifest.policy.queue_lane
        return [] unless queue

        list_cmd = ListQuery.new(prefix: nil, lane: queue)
        list_handler = Handlers::ListKeys.new(manifest: @manifest)
        result = list_handler.call(list_cmd, call)
        return [] unless result.is_a?(Textus::Result) && result.success?

        result.value.map { |r| r["key"] }
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
