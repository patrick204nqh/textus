# frozen_string_literal: true

require "time"

module Textus
  module Action
    class Pulse < Base
      verb :pulse
      summary "Delta since cursor — changed entries, pending proposals, index freshness."
      surfaces :cli, :mcp
      arg :since, Integer, session_default: :cursor,
                           description: "audit seq to diff from; defaults to the session cursor"

      def self.call(container:, call:, since: nil, **)
        manifest = container.manifest
        audit_log = container.audit_log
        root = container.root
        since ||= Textus::Store::Cursor.new(root: root, role: call.role).read

        result = {
          "cursor" => audit_log.latest_seq,
          "changed" => Textus::Action::Audit.call(container: container, seq_since: since),
          "pending_review" => review_keys(manifest, container),
          "contract_etag" => Textus::Value::Etag.for_contract(root),
          "index_etag" => index_etag(container),
        }

        Textus::Store::Cursor.new(root: root, role: call.role).write(result["cursor"])
        Success(result)
      end

      def self.review_keys(manifest, container)
        queue = manifest.policy.queue_lane
        return [] unless queue

        Textus::Action::List.leaf_keys(container: container, lane: queue)
      end

      def self.index_etag(container)
        path = container.manifest.resolver.resolve("artifacts.system.index").path
        File.exist?(path) ? container.file_store.etag(path) : nil
      rescue Textus::Error
        nil
      end
    end
  end
end
