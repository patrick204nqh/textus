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

    # Curated agent-facing verb catalog. This declares which verbs the operator
    # CLI surfaces and in what order — the editorial presentation. The summary of
    # each verb is a fact, not presentation: it is derived from `contract.summary`
    # at load time (ADR 0039). A literal "summary" survives here only for grouped
    # CLI tokens (schema/key/rule/hook) that aggregate several sub-contracts and so
    # have no single contract to derive from. CLI_VERBS itself is assigned in
    # textus.rb after Zeitwerk eager_load so all contract files are present.
    CURATED_CLI_VERBS = [
      { "name" => "boot" },
      { "name" => "list" },
      { "name" => "get" },
      { "name" => "where" },
      { "name" => "schema", "summary" => "schema operations: 'schema show KEY', 'schema diff', 'schema init', 'schema migrate'" },
      { "name" => "put" },
      { "name" => "propose" },
      { "name" => "accept" },
      { "name" => "key", "summary" => "key operations: 'key delete', 'key mv', 'key uid'" },
      { "name" => "reconcile" },
      { "name" => "audit" },
      { "name" => "blame" },
      { "name" => "rule", "summary" => "inspect effective rules: 'rule list', 'rule explain KEY'" },
      { "name" => "doctor" },
      { "name" => "hook", "summary" => "list and run registered hooks: 'hook list', 'hook run NAME'" },
      { "name" => "pulse" },
      { "name" => "capabilities" },
    ].freeze

    # verb token => contract.summary, for every Dispatcher verb that carries a
    # contract. The single source for a verb's one-line summary (ADR 0039).
    def self.contract_summaries
      Dispatcher::VERBS.values
                       .select { |k| k.respond_to?(:contract?) && k.contract? }
                       .to_h { |k| [k.contract.verb.to_s, k.contract.summary] }
    end

    # Build the CLI verb catalog: each summary is derived from its contract when
    # one exists, falling back to the curated editorial string for grouped tokens
    # (schema/key/rule/hook). Called once from textus.rb after eager_load.
    def self.build_cli_verbs
      summaries = contract_summaries
      CURATED_CLI_VERBS.map do |entry|
        derived = summaries[entry["name"]]
        derived ? entry.merge("summary" => derived) : entry
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
        # cannot call (audit/doctor are CLI-only; freshness is a Ruby-only
        # internal scan, ADR 0085) nor omit one it can
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

    def self.build(container:, lean: false)
      manifest = container.manifest
      etag = Textus::Etag.for_contract(container.root)

      if lean
        return {
          "protocol" => PROTOCOL_ID,
          "store_root" => container.root,
          "zones" => zones_for(manifest),
          "agent_quickstart" => agent_quickstart(manifest, container.audit_log),
          "contract_etag" => etag,
        }
      end

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
        "contract_etag" => etag,
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
