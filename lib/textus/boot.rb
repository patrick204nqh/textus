module Textus
  # Read-only "what's in this store and how do I use it" envelope.
  # A single call gives an agent the working model of a textus-managed
  # project: zones and their write authority, entries and their flags,
  # registered hooks, write flows, and the CLI verb catalog.
  #
  # Boot is side-effect-free.
  module Boot
    PROTOCOL_ID = PROTOCOL

    # Per-capability write-flow templates. Each lambda receives the user-facing
    # role name and the manifest, and returns guidance for that verb with the
    # live zone named by kind (ADR 0034). A role holding multiple verbs gets one
    # joined string; roles whose verbs have no template are omitted.
    WRITE_FLOW_TEMPLATES = {
      author: lambda do |name, manifest|
        "edit files in #{zone_label(manifest, :canon, "your canon zone")}, " \
          "then 'textus put KEY --as=#{name}'"
      end,
      keep: lambda do |name, manifest|
        "keep durable notes in #{zone_label(manifest, :workspace, "your workspace")}: " \
          "'textus put KEY --as=#{name}' (no accept needed)"
      end,
      propose: lambda do |name, manifest|
        authority = manifest.policy.roles_with_capability("author").first || "the author-holder"
        "propose changes by writing #{manifest.policy.queue_zone}.* entries with --as=#{name} " \
          "and a 'proposal:' frontmatter block; the #{authority} role runs 'textus accept' to apply"
      end,
      fetch: lambda do |name, manifest|
        "fetch #{zone_label(manifest, :quarantine, "quarantine")} entries with " \
          "'textus fetch KEY --as=#{name}' (uses the entry's declared action)"
      end,
      build: lambda do |_name, manifest|
        derived = zone_label(manifest, :derived, "derived")
        "'textus build' computes #{derived} entries from projections; " \
          "#{derived} files are never hand-edited"
      end,
    }.freeze

    def self.write_flows_for(manifest)
      manifest.data.role_caps.each_with_object({}) do |(name, caps), acc|
        flows = caps.filter_map do |verb|
          tmpl = WRITE_FLOW_TEMPLATES[verb.to_sym]
          tmpl&.call(name, manifest)
        end
        acc[name] = flows.join(" / ") unless flows.empty?
      end
    end

    # Human-readable name(s) for the live zone(s) of a given kind, or `fallback`
    # when the manifest declares none. Lets write-flow guidance name the live
    # zone by kind instead of a hardcoded instance name (ADR 0034).
    def self.zone_label(manifest, kind, fallback)
      zones = manifest.policy.zones_of_kind(kind)
      zones.empty? ? fallback : zones.join(", ")
    end

    # Static, store-independent parts of the agent-facing protocol. The
    # `recipes` and `role_resolution` blocks are derived per-manifest in
    # agent_protocol(...) because zone and role names are user-configurable.
    AGENT_PROTOCOL_TEMPLATE = {
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
    }.freeze

    # Curated agent-facing verb catalog. For verbs that have a Dispatcher contract,
    # the summary is derived from `contract.summary` at load time (ADR 0039). The
    # editorial strings below are the fallback for CLI-only verbs without contracts.
    # CLI_VERBS itself is assigned in textus.rb after Zeitwerk eager_load so that
    # all contract-declaring files are loaded before derivation runs.
    CURATED_CLI_VERBS = [
      { "name" => "boot" },
      { "name" => "list" },
      { "name" => "get" },
      { "name" => "where", "summary" => "resolve a key to its zone and path without reading" },
      { "name" => "schema", "summary" => "schema operations: 'schema show KEY', 'schema diff', 'schema init', 'schema migrate'" },
      { "name" => "put" },
      { "name" => "propose" },
      { "name" => "accept",   "summary" => "apply a queued proposal to its target zone; requires the author capability" },
      { "name" => "key",      "summary" => "key operations: 'key delete', 'key mv', 'key uid'" },
      { "name" => "build",    "summary" => "materialize derived entries; publish_to and publish_tree fan out copies" },
      { "name" => "tend" },
      { "name" => "freshness", "summary" => "per-entry lifecycle report (status, age, ttl, on_expire action)" },
      { "name" => "audit",    "summary" => "query .textus/audit.log with filters (key, role, since, correlation-id, ...)" },
      { "name" => "blame",    "summary" => "audit rows for one key joined with git commit metadata" },
      { "name" => "rule",     "summary" => "inspect effective rules: 'rule list', 'rule explain KEY'" },
      { "name" => "doctor",   "summary" => "health-check the store (missing schemas, illegal keys, sentinel drift, etc.)" },
      { "name" => "hook",     "summary" => "list and run registered hooks: 'hook list', 'hook run NAME'" },
      { "name" => "pulse" },
      { "name" => "capabilities" },
    ].freeze

    # Build the CLI verb catalog by deriving each summary from the corresponding
    # Dispatcher contract when one exists, falling back to the editorial string for
    # CLI-only verbs without a contract (e.g. accept, build, where). Called once
    # from textus.rb after eager_load so all contract files are present.
    def self.build_cli_verbs
      by_contract = Dispatcher::VERBS.values
                                     .select { |k| k.respond_to?(:contract?) && k.contract? }
                                     .to_h { |k| [k.contract.verb.to_s, k.contract.summary] }

      CURATED_CLI_VERBS.map do |entry|
        derived = by_contract[entry["name"]]
        if derived
          entry.merge("summary" => derived)
        else
          entry
        end
      end
    end

    def self.agent_quickstart(manifest, audit_log)
      agent_role = manifest.policy.proposer_role

      writable_zones = manifest.data.declared_zone_kinds.keys.each_with_object([]) do |zname, acc|
        acc << zname if agent_role && manifest.policy.zone_writers(zname).include?(agent_role)
      end

      propose_zone = manifest.policy.propose_zone_for(agent_role)

      {
        # Both verb lists derive from the MCP catalog (ADR 0056, ADR 0057): the
        # agent's real read and write surface, named as verbs the agent calls —
        # not CLI strings. read_verbs can neither advertise a verb the agent
        # cannot call (audit/freshness/doctor are CLI-only) nor omit one it can
        # (schema_show/rules); write_verbs drops the old `put KEY --as=… --stdin` CLI
        # framing (role is connection-resolved over MCP; there is no stdin).
        # writable_zones / propose_zone below carry the agent's write authority.
        "read_verbs" => Textus::MCP::Catalog.read_verbs,
        "write_verbs" => agent_role ? Textus::MCP::Catalog.write_verbs : [],
        "writable_zones" => writable_zones,
        "propose_zone" => propose_zone,
        "latest_seq" => audit_log.latest_seq,
      }
    end

    # Recipes reference verbs, not a transport's CLI strings (ADR 0056): every
    # step names a verb the agent can call (each transport frames it — CLI as
    # `textus get KEY`, MCP as the `get` tool) or is a plain build step. This
    # keeps shell lines out of the surface an MCP agent reads.
    def self.recipes(manifest)
      queue = manifest.policy.queue_zone
      feeds = zone_label(manifest, :quarantine, "the quarantine zone")
      {
        "read" => {
          "purpose" => "find and read an entry",
          "steps" => [
            "list (zone:, prefix:) — discover keys without reading bodies",
            "get KEY — returns the entry envelope",
          ],
        },
        "write" => {
          "purpose" => "create or update an entry",
          "steps" => [
            "schema KEY — learn the _meta field shape (required, optional, field types) before writing",
            "assemble an envelope: { _meta: {…}, body: \"…\" }",
            "put KEY — persist it (role-gated); pass if_etag to guard a concurrent edit",
          ],
        },
        "propose" => {
          "purpose" => "agent suggests a change for human review",
          "agent_steps" => [
            "propose KEY — writes the change into the #{queue} zone for review",
          ],
          "human_steps" => [
            "accept #{queue}.KEY — promotes the proposal into its target zone",
          ],
        },
        "fetch" => {
          "purpose" => "refresh stale quarantine-zone caches from their declared intake",
          "steps" => [
            "pulse — its `stale` list names entries past their ttl",
            "fetch_all (zone: #{feeds}) — re-pull the stale entries",
          ],
        },
      }
    end

    def self.agent_protocol(manifest)
      AGENT_PROTOCOL_TEMPLATE.merge(
        "recipes" => recipes(manifest),
        "role_resolution" => {
          "summary" => "write role is resolved in order: --as flag, TEXTUS_ROLE env var, .textus/role file, " \
                       "then a transport default ('human' for CLI, 'agent' for MCP)",
          "roles" => manifest.data.role_caps.keys,
          "ref" => "SPEC.md §5",
        },
      )
    end

    def self.build(container:)
      manifest = container.manifest
      {
        "protocol" => PROTOCOL_ID,
        "store_root" => container.root,
        "zones" => zones_for(manifest),
        "entries" => entries_for(manifest),
        "hooks" => hooks_for_container(container),
        "write_flows" => write_flows_for(manifest),
        "cli_verbs" => CLI_VERBS.map(&:dup),
        "agent_protocol" => agent_protocol(manifest),
        "agent_quickstart" => agent_quickstart(manifest, container.audit_log),
        "docs" => { "spec" => "SPEC.md", "example" => "examples/project/" },
      }
    end

    def self.zones_for(manifest)
      manifest.data.declared_zone_kinds.keys.map do |name|
        row = { "name" => name, "writers" => manifest.policy.zone_writers(name) }
        kind = manifest.policy.declared_kind(name)
        row["kind"] = kind.to_s if kind
        purpose = manifest.data.zone_descs[name]
        row["purpose"] = purpose if purpose && !purpose.empty?
        row
      end
    end

    def self.entries_for(manifest)
      manifest.data.entries.map do |e|
        derived = manifest.policy.derived_zone?(e.zone)
        {
          "key" => e.key,
          "zone" => e.zone,
          "schema" => e.schema,
          "nested" => e.is_a?(Textus::Manifest::Entry::Nested),
          "owner" => e.owner,
          "format" => e.format,
          "derived" => derived,
          "intake" => e.is_a?(Textus::Manifest::Entry::Intake),
          "publish_to" => Array(e.publish_to),
        }
      end
    end

    def self.hooks_for_container(container)
      hooks_for_container_internal(rpc: container.rpc, events: container.events)
    end

    def self.hooks_for_container_internal(rpc:, events:)
      sections = {}
      Hooks::Catalog::RPC.each_key do |event|
        sections[event.to_s] = rpc.names(event).map(&:to_s).sort
      end
      Hooks::Catalog::PUBSUB.each_key do |event|
        sections[event.to_s] = events.pubsub_handlers(event).map { |h| h[:name].to_s }.sort
      end
      sections
    end
  end
end
