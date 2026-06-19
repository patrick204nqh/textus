module Textus
  # Read-only "what's in this store and how do I use it" envelope.
  # Boot is side-effect-free. Reads from pre-computed artifacts and
  # the store catalog rather than computing inline.
  module Boot
    PROTOCOL_ID = PROTOCOL

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
      { "name" => "ingest" },
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
    ].freeze

    # verb token => contract.summary, for every Dispatcher verb that carries a
    # contract. The single source for a verb's one-line summary (ADR 0039).
    def self.contract_summaries
      Textus::Action::VERBS.values
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
        "read_verbs" => Textus::Surfaces::MCP::Catalog.read_verbs,
        "write_verbs" => agent_role ? Textus::Surfaces::MCP::Catalog.write_verbs : [],
        "writable_lanes" => writable_lanes,
        "propose_lane" => propose_lane,
        "latest_seq" => audit_log.latest_seq,
      }
    end

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

    def self.build(container:)
      manifest = container.manifest
      etag = Textus::Etag.for_contract(container.root)

      {
        "protocol" => PROTOCOL_ID,
        "store_root" => container.root,
        "contract_etag" => etag,
        "lanes" => lanes_for(manifest),
        "agent_quickstart" => agent_quickstart(manifest, container.audit_log),
        "orientation" => read_artifact_content(container, "artifacts.config.orientation"),
        "context" => read_boot_context(container),
        "agent_protocol" => agent_protocol(manifest),
      }.compact
    end

    def self.read_artifact_content(container, key)
      res = container.manifest.resolver.resolve(key)
      return nil unless res.path && File.exist?(res.path)

      call = Textus::Call.build(role: Textus::Role::DEFAULT)
      env  = Textus::Action::Get.new(key: key).call(container: container, call: call)
      env&.content
    rescue Textus::Error
      nil
    end

    def self.read_boot_context(container)
      res = container.manifest.resolver.resolve("knowledge.boot")
      return nil unless res.path && File.exist?(res.path)

      call = Textus::Call.build(role: Textus::Role::DEFAULT)
      env  = Textus::Action::Get.new(key: "knowledge.boot").call(container: container, call: call)
      body = env&.body&.strip
      body.nil? || body.empty? ? nil : body
    rescue Textus::Error
      nil
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
  end
end
