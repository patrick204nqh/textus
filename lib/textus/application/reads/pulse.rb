module Textus
  module Application
    module Reads
      # Aggregator over audit + freshness + review + doctor. One round-trip
      # for an agent's per-turn heartbeat. All component reads are existing
      # APIs; pulse is sugar with a stable envelope shape and a monotonic
      # cursor (seq).
      class Pulse
        def initialize(ctx:, manifest:, file_store:, audit_log:, root:, store:)
          @ctx        = ctx
          @manifest   = manifest
          @file_store = file_store
          @audit_log  = audit_log
          @root       = root
          @store      = store
        end

        def call(since: 0)
          changed = audit_changes_since(since)
          {
            "cursor" => @audit_log.latest_seq,
            "changed" => changed,
            "stale" => stale_keys,
            "pending_review" => review_keys,
            "doctor" => doctor_summary,
          }
        end

        private

        def audit_changes_since(seq)
          Reads::Audit.new(manifest: @manifest, root: @root, audit_log: @audit_log)
                      .call(seq_since: seq)
        end

        def stale_keys
          # Freshness rows use symbol keys: { key: "x.y", status: :stale, ... }
          rows = Reads::Freshness.new(ctx: @ctx, manifest: @manifest, file_store: @file_store).call
          rows.select { |r| r[:status] == :stale }.map { |r| r[:key] }
        end

        def review_keys
          # List constructor takes only manifest:; returns hashes with string keys.
          # Guard: zones is a Hash keyed by name string.
          return [] unless @manifest.zones.key?("review")

          rows = Reads::List.new(manifest: @manifest).call(zone: "review")
          rows.map { |r| r.is_a?(Hash) ? (r["key"] || r[:key]) : r }
        end

        def doctor_summary
          result  = Textus::Doctor.run(@store)
          issues  = result["issues"] || []
          {
            "ok" => result["ok"],
            "warn" => issues.count { |i| i["level"] == "warning" },
            "fail" => issues.count { |i| i["level"] == "error" },
          }
        end
      end
    end
  end
end
