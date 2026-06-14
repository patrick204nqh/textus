# frozen_string_literal: true

require "time"

module Textus
  module Action
    class Pulse < Base
      extend Textus::Contract::DSL

      verb :pulse
      summary "Delta since cursor — changed entries, stale, pending proposals, doctor summary."
      surfaces :cli, :mcp
      around :cursor
      arg :since, Integer, session_default: :cursor,
                           description: "audit seq to diff from; defaults to the session cursor"

      BURN = :sync

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
        @steps = container.steps

        freshness_rows = Pulse::Scanner.new.call(container: container, call: call)
        {
          "cursor" => @audit_log.latest_seq,
          "changed" => Textus::Action::Audit.new(seq_since: @since).call(container: container),
          "stale" => freshness_rows.select { |row| row[:status] == :expired }.map { |row| row[:key] },
          "pending_review" => review_keys,
          "doctor" => doctor_summary,
          "contract_etag" => Textus::Etag.for_contract(@root),
          "next_due_at" => soonest_due(freshness_rows),
          "hook_errors" => hook_errors_since(@since || 0),
        }
      end

      private

      def soonest_due(rows)
        times = rows.map { |row| row[:next_due_at] }.compact.map { |t| Time.parse(t) }
        return nil if times.empty?

        times.min.utc.iso8601
      end

      def review_keys
        queue = @manifest.policy.queue_lane
        return [] unless queue

        rows = Textus::Action::List.new(lane: queue).call(container: @container)
        rows.map { |row| row.is_a?(Hash) ? (row["key"] || row[:key]) : row }
      end

      def doctor_summary
        result = Textus::Doctor.build(container: @container)
        issues = result["issues"] || []
        {
          "ok" => result["ok"],
          "warn" => issues.count { |i| i["level"] == "warning" },
          "fail" => issues.count { |i| i["level"] == "error" },
        }
      end

      def hook_errors_since(seq)
        @steps.error_log.since(seq).map do |row|
          {
            "seq" => row[:seq],
            "event" => row[:event].to_s,
            "hook" => row[:hook].to_s,
            "key" => row[:key],
            "error_class" => row[:error_class],
            "error_message" => row[:error_message],
            "at" => row[:at],
          }
        end
      end
    end
  end
end
