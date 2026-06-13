module Textus
  # Read-only "what's in this store and how do I use it" envelope.
  # A single call gives an agent the working model of a textus-managed
  # project: lanes and their write authority, entries and their flags,
  # registered hooks, write flows, and the CLI verb catalog.
  #
  # Boot is side-effect-free.
  module Boot
    PROTOCOL_ID = PROTOCOL

    # Per-capability write-flow templates. Each lambda receives the user-facing
    # role name and the manifest, and returns guidance for that verb with the
    # live lane named by kind (ADR 0034). A role holding multiple verbs gets one
    # joined string; roles whose verbs have no template are omitted.
    WRITE_FLOW_TEMPLATES = {
      author: lambda do |name, manifest|
        "edit files in #{lane_label(manifest, :canon, "your canon lane")}, " \
          "then 'textus put KEY --as=#{name}'"
      end,
      keep: lambda do |name, manifest|
        "keep durable notes in #{lane_label(manifest, :workspace, "your workspace")}: " \
          "'textus put KEY --as=#{name}' (no accept needed)"
      end,
      propose: lambda do |name, manifest|
        authority = manifest.policy.roles_with_capability("author").first || "the author-holder"
        "propose changes by writing #{manifest.policy.queue_lane}.* entries with --as=#{name} " \
          "and a 'proposal:' frontmatter block; the #{authority} role runs 'textus accept' to apply"
      end,
      converge: lambda do |_name, manifest|
        machine = lane_label(manifest, :machine, "machine")
        "'textus drain' materializes derived #{machine} entries from their sources and " \
          "refreshes stale intake #{machine} entries from their declared source; " \
          "derived files are never hand-edited (reactive on canon writes, or a full pass on demand)"
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

    # Human-readable name(s) for the live lane(s) of a given kind, or `fallback`
    # when the manifest declares none. Lets write-flow guidance name the live
    # lane by kind instead of a hardcoded instance name (ADR 0034).
    def self.lane_label(manifest, kind, fallback)
      lanes = manifest.policy.lanes_of_kind(kind)
      lanes.empty? ? fallback : lanes.join(", ")
    end

    # Static, store-independent parts of the agent-facing protocol. The
    # `recipes` and `role_resolution` blocks are derived per-manifest in
    # agent_protocol(...) because lane and role names are user-configurable.
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
      { "name" => "enqueue" },
      { "name" => "key", "summary" => "key operations: 'key delete', 'key mv', 'key uid'" },
      { "name" => "drain" },
      { "name" => "audit" },
      { "name" => "blame" },
      { "name" => "rule", "summary" => "inspect effective rules: 'rule list', 'rule explain KEY'" },
      { "name" => "doctor" },
      { "name" => "jobs" },
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

      writable_lanes = manifest.data.declared_lane_kinds.keys.each_with_object([]) do |lane_name, acc|
        next unless agent_role

        verb = manifest.policy.verb_for_lane(lane_name)
        writers = manifest.policy.roles_with_capability(verb)
        acc << lane_name if writers.include?(agent_role)
      end

      propose_lane = manifest.policy.propose_lane_for(agent_role)

      {
        # Both verb lists derive from the MCP catalog (ADR 0056, ADR 0057): the
        # agent's real read and write surface, named as verbs the agent calls —
        # not CLI strings. read_verbs can neither advertise a verb the agent
        # cannot call (audit/doctor are CLI-only; freshness is a Ruby-only
        # internal scan, ADR 0085) nor omit one it can
        # (schema_show/rules); write_verbs drops the old `put KEY --as=… --stdin` CLI
        # framing (role is connection-resolved over MCP; there is no stdin).
        # writable_lanes / propose_lane below carry the agent's write authority.
        "read_verbs" => Textus::Surfaces::MCP::Catalog.read_verbs,
        "write_verbs" => agent_role ? Textus::Surfaces::MCP::Catalog.write_verbs : [],
        "writable_lanes" => writable_lanes,
        "propose_lane" => propose_lane,
        "latest_seq" => audit_log.latest_seq,
      }
    end

    # Recipes reference verbs, not a transport's CLI strings (ADR 0056): every
    # step names a verb the agent can call (each transport frames it — CLI as
    # `textus get KEY`, MCP as the `get` tool) or is a plain materialize step. This
    # keeps shell lines out of the surface an MCP agent reads.
    def self.recipes(manifest)
      queue = manifest.policy.queue_lane
      feeds = lane_label(manifest, :machine, "the machine lane")
      {
        "read" => {
          "purpose" => "find and read an entry",
          "steps" => [
            "list (lane:, prefix:) — discover keys without reading bodies",
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
            "propose KEY — writes the change into the #{queue} lane for review",
          ],
          "human_steps" => [
            "accept #{queue}.KEY — promotes the proposal into its target lane",
          ],
        },
        "drain" => {
          "purpose" => "keep the machine-maintained lanes fresh — re-pull stale intake entries from their declared source",
          "steps" => [
            "pulse — its `stale` list names entries past their ttl",
            "drain (lane: #{feeds}) — re-pull the stale entries",
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
          "lanes" => lanes_for(manifest),
          "agent_quickstart" => agent_quickstart(manifest, container.audit_log),
          "contract_etag" => etag,
        }
      end

      {
        "protocol" => PROTOCOL_ID,
        "store_root" => container.root,
        "lanes" => lanes_for(manifest),
        "entries" => entries_for(manifest),
        "hooks" => hooks_for_container(container),
        "write_flows" => write_flows_for(manifest),
        "cli_verbs" => CLI_VERBS.map(&:dup),
        "agent_protocol" => agent_protocol(manifest),
        "agent_quickstart" => agent_quickstart(manifest, container.audit_log),
        "contract_etag" => etag,
        "docs" => { "spec" => "SPEC.md", "example" => ".textus/" },
      }
    end

    def self.lanes_for(manifest)
      manifest.data.declared_lane_kinds.keys.map do |name|
        verb = manifest.policy.verb_for_lane(name)
        row = { "name" => name, "writers" => manifest.policy.roles_with_capability(verb) }
        kind = manifest.policy.declared_kind(name)
        row["kind"] = kind.to_s if kind
        purpose = manifest.data.lane_descs[name]
        row["purpose"] = purpose if purpose && !purpose.empty?
        row
      end
    end

    def self.entries_for(manifest)
      manifest.data.entries.map do |e|
        derived = e.derived?
        {
          "key" => e.key,
          "lane" => e.lane,
          "schema" => e.schema,
          "nested" => e.is_a?(Textus::Manifest::Entry::Nested),
          "owner" => e.owner,
          "format" => e.format,
          "derived" => derived,
          "intake" => e.intake?,
          "publish_to" => Array(e.publish_to),
        }
      end
    end

    def self.hooks_for_container(container)
      hooks_for_container_internal(steps: container.steps)
    end

    def self.hooks_for_container_internal(steps:)
      sections = {}
      rpc_kind_map = {
        resolve_handler: :fetch,
        transform_rows: :transform,
        validate: :validate,
      }
      Step::Catalog::RPC.each_key do |event|
        sections[event.to_s] = steps.names(rpc_kind_map.fetch(event)).map(&:to_s).sort
      end
      Step::Catalog::PUBSUB.each_key do |event|
        sections[event.to_s] = steps.pubsub_handlers(event).map { |h| h[:name].to_s }.sort
      end
      sections
    end
  end
end
