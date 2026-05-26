module Textus
  # Read-only "what's in this store and how do I use it" envelope.
  # A single call gives an agent the working model of a textus-managed
  # project: zones and their write authority, entries and their flags,
  # registered hooks, write flows, and the CLI verb catalog.
  #
  # Intro is side-effect-free.
  module Intro
    PROTOCOL_ID = PROTOCOL

    # Conventional zone purposes. Unknown zones (declared in the manifest
    # but not listed here) get no `purpose` field.
    ZONE_PURPOSES = {
      "identity" => "slow-changing identity; human-only writes",
      "working" => "active project state; humans, AI, and scripts share this surface",
      "intake" => "declared external inputs; script-refreshed via actions",
      "review" => "AI proposals awaiting human accept",
      "output" => "build-computed outputs; never hand-edited",
    }.freeze

    WRITE_FLOWS = {
      "human" => "edit files in identity/working zones, then 'textus put KEY --as=human'",
      "agent" => "propose changes by writing 'review.*' entries with --as=agent and a 'proposal:' frontmatter block; " \
                 "a human runs 'textus accept' to apply",
      "runner" => "refresh intake entries with 'textus refresh KEY --as=runner' (uses the entry's declared action)",
      "builder" => "'textus build' computes output entries from projections; output files are never hand-edited",
    }.freeze

    # Static, store-independent guide to the agent-facing protocol. Surfaced
    # under the new top-level `agent_protocol` key in Intro.run. Recipes
    # describe CLI verbs (not Ruby Operations) because the audience is an
    # agent driving textus from the command line.
    AGENT_PROTOCOL = {
      "envelope_shape" => {
        "summary" => "every read/write payload is a JSON envelope with _meta, body, uid, and etag",
        "fields" => {
          "_meta" => "hash of structured frontmatter; schema-validated per entry family",
          "body" => "string payload (markdown/text) or nil for json/yaml formats where body lives in _meta",
          "uid" => "stable 16-char hex identifier; preserved across writes and key renames",
          "etag" => "content hash; pass back on writes to detect concurrent edits",
        },
        "ref" => "SPEC.md §8",
      },
      "role_resolution" => {
        "summary" => "write role is resolved in order: --as flag, TEXTUS_ROLE env var, .textus/role file, default human",
        "roles" => %w[human agent runner builder],
        "ref" => "SPEC.md §5",
      },
      "recipes" => {
        "read" => {
          "purpose" => "find and read an entry",
          "steps" => [
            "textus list --zone=ZONE --prefix=PREFIX  # discover keys",
            "textus get KEY                            # returns envelope JSON",
          ],
        },
        "write" => {
          "purpose" => "create or update an entry",
          "steps" => [
            "textus schema get FAMILY                  # learn the _meta field shape",
            "build an envelope JSON: {_meta: {...}, body: \"...\"}",
            "echo ENVELOPE | textus put KEY --as=ROLE --stdin",
          ],
        },
        "propose" => {
          "purpose" => "agent suggests a change for human review",
          "agent_steps" => [
            "echo ENVELOPE | textus put review.KEY --as=agent --stdin",
          ],
          "human_steps" => [
            "textus accept review.KEY --as=human       # promotes the proposal to its target zone",
          ],
        },
        "refresh" => {
          "purpose" => "rebuild stale intake-zone caches from their declared actions",
          "steps" => [
            "textus freshness --zone=intake            # report fresh/stale per entry",
            "textus refresh stale --zone=intake --as=runner",
          ],
        },
      },
    }.freeze

    # The CLI verb catalog. Truth lives here; do not derive dynamically.
    # Agents that read intro should see a stable shape regardless of how
    # verb implementations evolve.
    CLI_VERBS = [
      { "name" => "intro",    "summary" => "this output — orientation for agents and tools" },
      { "name" => "list",     "summary" => "enumerate keys (optional --prefix)" },
      { "name" => "get",      "summary" => "read an entry; envelope with _meta, body, uid, etag" },
      { "name" => "where",    "summary" => "resolve a key to its zone and path without reading" },
      { "name" => "schema",   "summary" => "field shape for a key family" },
      { "name" => "put",      "summary" => "write an entry; --as=<role>, --stdin payload" },
      { "name" => "accept",   "summary" => "apply a review.* proposal; --as=human only" },
      { "name" => "key",      "summary" => "key operations: 'key mv', 'key uid', 'key normalize'" },
      { "name" => "delete",   "summary" => "delete an entry; --as=<role>" },
      { "name" => "build",    "summary" => "materialize output entries; publish_to and publish_each fan out copies" },
      { "name" => "refresh",  "summary" => "run an action for an intake entry" },
      { "name" => "freshness", "summary" => "per-entry freshness report (status, age, ttl, on_stale)" },
      { "name" => "audit", "summary" => "query .textus/audit.log with filters (key, role, since, correlation-id, ...)" },
      { "name" => "blame", "summary" => "audit rows for one key joined with git commit metadata" },
      { "name" => "rule", "summary" => "inspect effective rules: 'rule list', 'rule explain KEY'" },
      { "name" => "doctor", "summary" => "health-check the store (missing schemas, illegal keys, sentinel drift, etc.)" },
      { "name" => "hook",
        "summary" => "list and run registered hooks: 'hook list', 'hook run NAME'" },
    ].freeze

    def self.run(store)
      {
        "protocol" => PROTOCOL_ID,
        "store_root" => store.root,
        "zones" => zones_for(store),
        "entries" => entries_for(store),
        "hooks" => hooks_for(store),
        "write_flows" => WRITE_FLOWS.dup,
        "cli_verbs" => CLI_VERBS.map(&:dup),
        "agent_protocol" => AGENT_PROTOCOL,
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
        derived = store.manifest.zone_writers(e.zone).include?("builder")
        {
          "key" => e.key,
          "zone" => e.zone,
          "schema" => e.schema,
          "nested" => e.nested ? true : false,
          "owner" => e.owner,
          "format" => e.format,
          "derived" => derived,
          "intake" => !e.intake_handler.nil?,
          "publish_to" => Array(e.publish_to),
          "publish_each" => e.publish_each,
        }
      end
    end

    def self.hooks_for(store)
      reg = store.registry
      sections = {}
      Hooks::Registry::EVENTS.each do |event, spec|
        case spec[:mode]
        when :rpc
          sections[event.to_s] = reg.rpc_names(event).map(&:to_s).sort
        when :pubsub
          sections[event.to_s] = reg.pubsub_handlers(event).map { |h| h[:name].to_s }.sort
        end
      end
      sections
    end
  end
end
