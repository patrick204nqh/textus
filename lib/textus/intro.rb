module Textus
  # Read-only "what's in this store and how do I use it" envelope.
  # A single call gives an agent the working model of a textus-managed
  # project: zones and their write authority, entries and their flags,
  # registered extensions, write flows, and the CLI verb catalog.
  #
  # Intro is side-effect-free.
  module Intro
    PROTOCOL_ID = "textus/1".freeze

    # Conventional zone purposes. Unknown zones (declared in the manifest
    # but not listed here) get no `purpose` field.
    ZONE_PURPOSES = {
      "canon" => "slow-changing identity; human-only writes",
      "working" => "active project state; humans, AI, and scripts share this surface",
      "intake" => "declared external inputs; script-refreshed via actions",
      "pending" => "AI proposals awaiting human accept",
      "derived" => "build-computed outputs; never hand-edited",
    }.freeze

    WRITE_FLOWS = {
      "human" => "edit files in canon/working zones, then 'textus put KEY --as=human'",
      "ai" => "propose changes by writing 'pending.*' entries with --as=ai and a 'proposal:' frontmatter block; " \
              "a human runs 'textus accept' to apply",
      "script" => "refresh intake entries with 'textus refresh KEY --as=script' (uses the entry's declared action)",
      "build" => "'textus build' computes derived entries from projections; derived files are never hand-edited",
    }.freeze

    # The CLI verb catalog. Truth lives here; do not derive dynamically.
    # Agents that read intro should see a stable shape regardless of how
    # verb implementations evolve.
    CLI_VERBS = [
      { "name" => "intro",    "summary" => "this output — orientation for agents and tools" },
      { "name" => "list",     "summary" => "enumerate keys (optional --prefix)" },
      { "name" => "get",      "summary" => "read an entry; envelope with frontmatter, body, uid, etag" },
      { "name" => "where",    "summary" => "resolve a key to its zone and path without reading" },
      { "name" => "schema",   "summary" => "field shape for a key family" },
      { "name" => "put",      "summary" => "write an entry; --as=<role>, --stdin payload" },
      { "name" => "accept",   "summary" => "apply a pending.* proposal; --as=human only" },
      { "name" => "mv",       "summary" => "rename a key in place; uid preserved, audit row written" },
      { "name" => "delete",   "summary" => "delete an entry; --as=<role>" },
      { "name" => "build",    "summary" => "materialize derived entries; publish_to and publish_each fan out copies" },
      { "name" => "refresh",  "summary" => "run an action for an intake entry" },
      { "name" => "stale",    "summary" => "list derived/intake entries past their freshness check" },
      { "name" => "doctor",   "summary" => "health-check the store (missing schemas, illegal keys, sentinel drift, etc.)" },
      { "name" => "migrate-keys", "summary" => "rename files whose basenames violate the strict key grammar" },
      { "name" => "extensions", "summary" => "list registered actions, reducers, doctor_checks, declared hooks" },
    ].freeze

    def self.run(store)
      {
        "protocol" => PROTOCOL_ID,
        "store_root" => store.root,
        "zones" => zones_for(store),
        "entries" => entries_for(store),
        "extensions" => extensions_for(store),
        "write_flows" => WRITE_FLOWS.dup,
        "cli_verbs" => CLI_VERBS.map(&:dup),
        "docs" => { "spec" => "SPEC.md", "example" => "examples/claude-plugin/" },
      }
    end

    def self.zones_for(store)
      store.manifest.zones.map do |name, writers|
        row = { "name" => name, "writers" => Array(writers) }
        purpose = ZONE_PURPOSES[name]
        row["purpose"] = purpose if purpose
        row
      end
    end

    def self.entries_for(store)
      store.manifest.entries.map do |e|
        derived = store.manifest.zone_writers(e.zone).include?("build")
        {
          "key" => e.key,
          "zone" => e.zone,
          "schema" => e.schema,
          "nested" => e.nested ? true : false,
          "owner" => e.owner,
          "format" => e.format,
          "derived" => derived,
          "intake" => !e.action.nil?,
          "publish_to" => Array(e.publish_to),
          "publish_each" => e.publish_each,
        }
      end
    end

    def self.extensions_for(store)
      reg = store.registry
      reducers = reg.reducer_names.map(&:to_s).sort
      actions = reg.action_names.map(&:to_s).sort
      doctor_checks = reg.doctor_check_names.map(&:to_s).sort
      hooks = reg.hook_events.flat_map do |evt|
        reg.hooks(evt).map { |h| { "event" => evt.to_s, "name" => h[:name].to_s } }
      end.sort_by { |h| [h["event"], h["name"]] }
      {
        "reducers" => reducers,
        "actions" => actions,
        "doctor_checks" => doctor_checks,
        "hooks" => hooks,
      }
    end
  end
end
