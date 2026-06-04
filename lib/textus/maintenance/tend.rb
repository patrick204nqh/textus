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
        fetch  = apply_fetch(prefix, zone)
        retain = apply_retain(prefix, zone)
        health = Read::Doctor.new(container: @container, call: @call).call

        {
          "protocol" => Textus::PROTOCOL,
          "ok" => fetch.fetch("ok", true) && retain.fetch("ok", true),
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
    end
  end
end
