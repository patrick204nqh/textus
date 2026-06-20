# frozen_string_literal: true

require "time"

module Textus
  module Action
    class Pulse < Base
      extend Textus::Contract::DSL

      verb :pulse
      summary "Delta since cursor — changed entries, pending proposals, index freshness."
      surfaces :cli, :mcp
      arg :since, Integer, session_default: :cursor,
                           description: "audit seq to diff from; defaults to the session cursor"

      def initialize(since: nil)
        super()
        @since = since
      end

      def call(container:, call:)
        @container = container
        @call = call
        @manifest = container.manifest
        @audit_log = container.audit_log
        @root = container.root

        {
          "cursor" => @audit_log.latest_seq,
          "changed" => Textus::Action::Audit.new(seq_since: @since).call(container: container),
          "pending_review" => review_keys,
          "contract_etag" => Textus::Value::Etag.for_contract(@root),
          "index_etag" => index_etag(container),
        }
      end

      private

      def review_keys
        queue = @manifest.policy.queue_lane
        return [] unless queue

        rows = Textus::Action::List.new(lane: queue).call(container: @container)
        rows.map { |row| row.is_a?(Hash) ? (row["key"] || row[:key]) : row }
      end

      def index_etag(container)
        path = container.manifest.resolver.resolve("artifacts.system.index").path
        File.exist?(path) ? container.file_store.etag(path) : nil
      rescue Textus::Error
        nil
      end
    end
  end
end
