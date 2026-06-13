require "time"

module Textus
  module Read
    # Aggregator over audit + freshness + review + doctor. One round-trip
    # for an agent's per-turn heartbeat. All component reads are existing
    # APIs; pulse is sugar with a stable envelope shape and a monotonic
    # cursor (seq).
    class Pulse
      extend Textus::Contract::DSL

      verb     :pulse
      summary  "Delta since cursor — changed entries, stale, pending proposals, doctor summary."
      surfaces :cli, :mcp
      around   :cursor
      arg :since, Integer, session_default: :cursor, description: "audit seq to diff from; defaults to the session cursor"

      def initialize(container:, call:)
        @container  = container
        @call       = call
        @manifest   = container.manifest
        @file_store = container.file_store
        @audit_log  = container.audit_log
        @root       = container.root
        @steps = container.steps
      end

      def call(since: 0)
        freshness_rows = freshness.call
        {
          "cursor" => @audit_log.latest_seq,
          "changed" => audit_changes_since(since),
          "stale" => freshness_rows.select { |r| r[:status] == :expired }.map { |r| r[:key] },
          "pending_review" => review_keys,
          "doctor" => doctor_summary,
          "contract_etag" => contract_etag,
          "next_due_at" => soonest_due(freshness_rows),
          "hook_errors" => hook_errors_since(since),
        }
      end

      private

      def audit_changes_since(seq)
        Read::Audit.new(container: @container).call(seq_since: seq)
      end

      def freshness
        @freshness ||= Read::Freshness.new(container: @container, call: @call)
      end

      def soonest_due(rows)
        times = rows.map { |r| r[:next_due_at] }.compact.map { |t| Time.parse(t) }
        return nil if times.empty?

        times.min.utc.iso8601
      end

      def review_keys
        # The single queue zone (kind: queue; schema guarantees ≤1), derived
        # from the manifest rather than a hardcoded zone name (ADR 0034 / D1).
        queue = @manifest.policy.queue_zone
        return [] unless queue

        rows = Read::List.new(container: @container).call(zone: queue)
        rows.map { |r| r.is_a?(Hash) ? (r["key"] || r[:key]) : r }
      end

      def doctor_summary
        result  = Textus::Doctor.build(container: @container)
        issues  = result["issues"] || []
        {
          "ok" => result["ok"],
          "warn" => issues.count { |i| i["level"] == "warning" },
          "fail" => issues.count { |i| i["level"] == "error" },
        }
      end

      def contract_etag
        Textus::Etag.for_contract(@root)
      end

      def hook_errors_since(seq)
        @steps.error_log.since(seq).map do |r|
          {
            "seq" => r[:seq],
            "event" => r[:event].to_s,
            "hook" => r[:hook].to_s,
            "key" => r[:key],
            "error_class" => r[:error_class],
            "error_message" => r[:error_message],
            "at" => r[:at],
          }
        end
      end
    end
  end
end
