module Textus
  module Maintenance
    # Composite upkeep pass (ADR 0078): refresh stale intake, apply retention,
    # then report residual health — in that order. Adds no new storage semantics
    # and no authority: it constructs and invokes the existing FetchAll /
    # RetentionSweep / Doctor use-cases with the CALLER's own `call` (role), so
    # each sub-op stays gated exactly as it is on its own. Deliberately NOT
    # self-elevating — the contrast with `build` (ADR 0076).
    class Tend
      extend Textus::Contract::DSL

      verb     :tend
      summary  "Run upkeep: refresh stale intake, apply retention, report health."
      surfaces :cli, :mcp
      cli      "tend"
      arg :prefix,  String, description: "restrict every pass to keys under this dotted prefix"
      arg :zone,    String, description: "restrict every pass to entries in this zone"
      arg :dry_run, :boolean, default: false,
                              description: "when true, report what each pass WOULD do without applying; " \
                                           "defaults to false, so omitting it refreshes and expires immediately"

      def initialize(container:, call:)
        @container = container
        @call      = call
      end

      def call(prefix: nil, zone: nil, dry_run: false)
        fetch  = dry_run ? preview_fetch(prefix, zone)  : apply_fetch(prefix, zone)
        retain = dry_run ? preview_retain(prefix, zone) : apply_retain(prefix, zone)
        health = Read::Doctor.new(container: @container, call: @call).call

        {
          "protocol" => Textus::PROTOCOL,
          "ok" => fetch["ok"] && retain["ok"],
          "dry_run" => dry_run,
          "fetch" => fetch,
          "retain" => retain,
          "health" => health,
        }
      end

      private

      def apply_fetch(prefix, zone)
        Write::FetchAll.new(container: @container, call: @call)
                       .call(prefix: prefix, zone: zone)
      end

      def apply_retain(prefix, zone)
        Write::RetentionSweep.new(container: @container, call: @call)
                             .call(prefix: prefix, zone: zone)
      end

      # Preview = the read side of each pass, with zero writes. Uses
      # Write::FetchAll::ACTIONABLE_REASON (shared constant) so the filter
      # stays in sync with the real apply path.
      def preview_fetch(prefix, zone)
        rows = Read::Stale.new(container: @container, call: @call)
                          .call(prefix: prefix, zone: zone)
        would = rows.select { |r| (r["reason"] || r[:reason]).to_s.match?(Write::FetchAll::ACTIONABLE_REASON) }
                    .map { |r| r["key"] || r[:key] }
        { "ok" => true, "would_fetch" => would }
      end

      # Read::Retainable returns exactly the rows RetentionSweep would consume.
      def preview_retain(prefix, zone)
        rows = Read::Retainable.new(container: @container, call: @call)
                               .call(prefix: prefix, zone: zone)
        { "ok" => true,
          "would_expire" => rows.reject { |r| r["action"] == "archive" }.map { |r| r["key"] },
          "would_archive" => rows.select { |r| r["action"] == "archive" }.map { |r| r["key"] } }
      end
    end
  end
end
