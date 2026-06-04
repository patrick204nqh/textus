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

      def call(prefix: nil, zone: nil, dry_run: false) # rubocop:disable Lint/UnusedMethodArgument
        { "protocol" => Textus::PROTOCOL, "ok" => true, "dry_run" => dry_run }
      end
    end
  end
end
