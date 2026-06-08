require "fileutils"

module Textus
  module Maintenance
    # Two-phase convergence pass (ADR 0093). Replaces the old Lifecycle-reporter
    # sweep.
    #
    # Phase 1 — Produce (non-destructive): re-render ALL derived entries (cheap,
    # idempotent) plus every intake entry past its source.ttl (stale-only, so
    # external sources are not hammered). Driven by Produce::Engine.
    #
    # Phase 2 — Retention sweep (destructive): drop or archive entries past their
    # retention ttl. Driven by Domain::Retention::Sweep. The old refresh/warn
    # actions are gone — intake re-pull is now Produce's responsibility.
    class Reconcile
      extend Textus::Contract::DSL

      verb     :reconcile
      summary  "Run the convergence pass: produce derived + stale intake, then drop/archive aged entries; report health."
      surfaces :cli, :mcp
      cli      "reconcile"
      arg :prefix,  String, description: "restrict the sweep to keys under this dotted prefix"
      arg :zone,    String, description: "restrict the sweep to entries in this zone"
      arg :dry_run, :boolean, default: false,
                              description: "when true, report what the pass WOULD do without applying; " \
                                           "defaults to false, so omitting it produces + drops/archives immediately"

      def initialize(container:, call:)
        @container = container
        @call      = call
      end

      def call(prefix: nil, zone: nil, dry_run: false)
        file_stat = Textus::Ports::Storage::FileStat.new
        retention_rows = Textus::Domain::Retention::Sweep.new(
          manifest: @container.manifest, file_stat: file_stat, clock: Textus::Ports::Clock.new,
        ).call(prefix: prefix, zone: zone)

        produce_keys = produce_scope(prefix, zone, file_stat)
        health = Read::Doctor.new(container: @container, call: @call).call
        return dry_run_result(produce_keys, retention_rows, health) if dry_run

        Textus::Ports::BuildLock.with(root: @container.root) do
          produced = Textus::Produce::Engine.new(container: @container, call: @call).call(keys: produce_keys)
          swept = apply(retention_rows)
          publish_failed(swept[:failed]) unless swept[:failed].empty?
          apply_result(produced, swept, health)
        end
      end

      private

      # The full produce scope (ADR 0093): every derived entry (always
      # re-render — cheap, idempotent), every entry that mirrors a publish_tree
      # (the nested-subtree publishers, ADR 0047 — mirrored each pass so a
      # removed source leaf is swept from the published tree), every authored
      # leaf with a `publish.to` target (the single-file canon publishers —
      # docs/README.md, the architecture index, the root README; ADR 0103 —
      # converged each pass so a stale published copy is rewritten and the
      # `reconcile`-is-a-no-op check guards them), plus every intake entry past
      # its source.ttl (re-pull only when due, so external sources aren't
      # hammered). Ttl-less intake entries (:no_policy) are skipped — they have
      # no freshness contract and are never auto-re-pulled (ADR 0099). All are
      # idempotent: publish writes only when the target's content changed.
      def produce_scope(prefix, zone, file_stat)
        publishable = @container.manifest.data.entries
                                .select { |e| e.derived? || !e.publish_tree.nil? || !e.publish_to.empty? }
                                .select { |e| in_scope?(e, prefix, zone) }.map(&:key)
        stale_intake = Textus::Domain::Freshness::Evaluator.new(
          manifest: @container.manifest, file_stat: file_stat, clock: Textus::Ports::Clock.new,
        ).stale_intake_keys(prefix: prefix, zone: zone)
        (publishable + stale_intake).uniq
      end

      def in_scope?(entry, prefix, zone)
        return false if zone && entry.zone != zone
        return false if prefix && !entry.key.start_with?(prefix)

        true
      end

      def dry_run_result(produce_keys, rows, health)
        {
          "protocol" => Textus::PROTOCOL, "ok" => true, "dry_run" => true,
          "would_produce" => produce_keys,
          "would_drop" => action_keys(rows, "drop"),
          "would_archive" => action_keys(rows, "archive"),
          "health" => health
        }
      end

      def apply_result(produced, swept, health)
        {
          "protocol" => Textus::PROTOCOL,
          "ok" => produced[:failed].empty? && swept[:failed].empty?,
          "dry_run" => false,
          "produced" => produced[:produced],
          "produce_failed" => produced[:failed],
          "dropped" => swept[:dropped], "archived" => swept[:archived],
          "failed" => swept[:failed],
          "health" => health
        }
      end

      def action_keys(rows, action)
        rows.select { |r| r["action"] == action }.map { |r| r["key"] }
      end

      def publish_failed(failed)
        @container.events.publish(
          :reconcile_failed,
          ctx: Textus::Hooks::Context.for(container: @container, call: @call),
          failed: failed,
        )
      end

      # Phase 2: destructive retention only (drop/archive). No refresh — intake
      # re-pull is Produce's job (Phase 1). ADR 0093.
      def apply(rows)
        Textus::Maintenance::Retention::Apply.new(container: @container, call: @call).call(rows)
      end
    end
  end
end
