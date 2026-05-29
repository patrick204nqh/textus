require "digest"
require "time"

module Textus
  module Application
    module Read
      # Aggregator over audit + freshness + review + doctor. One round-trip
      # for an agent's per-turn heartbeat. All component reads are existing
      # APIs; pulse is sugar with a stable envelope shape and a monotonic
      # cursor (seq).
      module Pulse
        def self.call(*, session:, ctx:, caps:, **)
          Impl.new(ctx: ctx, caps: caps, session: session).call(*, **)
        end

        class Impl
          def initialize(ctx:, caps:, session:)
            @ctx = ctx
            @caps = caps
            @manifest   = caps.manifest
            @file_store = caps.file_store
            @audit_log  = caps.audit_log
            @root       = caps.root
            @events     = caps.events
            @session    = session
          end

          def call(since: 0)
            freshness_rows = freshness.call
            {
              "cursor" => @audit_log.latest_seq,
              "changed" => audit_changes_since(since),
              "stale" => freshness_rows.select { |r| r[:status] == :stale }.map { |r| r[:key] },
              "pending_review" => review_keys,
              "doctor" => doctor_summary,
              "manifest_etag" => manifest_etag,
              "next_due_at" => soonest_due(freshness_rows),
              "hook_errors" => hook_errors_since(since),
            }
          end

          private

          def audit_changes_since(seq)
            Read::Audit.new(container: @caps).call(seq_since: seq)
          end

          def freshness
            @freshness ||= Read::Freshness.new(container: @caps, call: @ctx)
          end

          def soonest_due(rows)
            times = rows.map { |r| r[:next_due_at] }.compact.map { |t| Time.parse(t) }
            return nil if times.empty?

            times.min.utc.iso8601
          end

          def review_keys
            # List constructor takes only manifest:; returns hashes with string keys.
            # Guard: zones is a Hash keyed by name string.
            return [] unless @manifest.data.zones.key?("review")

            rows = Read::List.new(container: @caps).call(zone: "review")
            rows.map { |r| r.is_a?(Hash) ? (r["key"] || r[:key]) : r }
          end

          def doctor_summary
            result  = Textus::Doctor.run(@session)
            issues  = result["issues"] || []
            {
              "ok" => result["ok"],
              "warn" => issues.count { |i| i["level"] == "warning" },
              "fail" => issues.count { |i| i["level"] == "error" },
            }
          end

          def manifest_etag
            Digest::SHA256.hexdigest(File.read(File.join(@root, "manifest.yaml")))
          end

          def hook_errors_since(seq)
            @events.error_log.since(seq).map do |r|
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
  end
end

Textus::Application::UseCase.register(:pulse, Textus::Application::Read::Pulse, caps: :read)
