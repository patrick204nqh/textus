# rubocop:disable Metrics/BlockLength
Textus.workflow "boot" do
  match "artifacts.boot"

  step :build do |_, ctx|
    manifest = ctx.container.manifest
    reader = ctx.container.reader

    fetch = ->(key) { begin; reader.read(key); rescue StandardError; nil; end }

    # Project context (was artifacts.config.orientation)
    project_env = fetch.call("knowledge.project")
    project = project_env&.meta || {}

    runbook_keys = manifest.resolver.enumerate(prefix: "knowledge.runbooks").map { |r| r[:key] }
    runbooks = runbook_keys.filter_map do |k|
      env = fetch.call(k)
      env&.meta
    end

    # Lanes (was Boot.lanes_for)
    lanes = manifest.data.declared_lane_kinds.keys.map do |name|
      verb = manifest.policy.verb_for_lane(name)
      row  = { "name" => name, "writers" => manifest.policy.roles_with_capability(verb) }
      kind = manifest.policy.declared_kind(name)
      row["kind"] = kind.to_s if kind
      desc = manifest.data.lane_descs[name]
      row["purpose"] = desc if desc && !desc.empty?
      row
    end

    # Agent quickstart (was Boot.agent_quickstart — minus latest_seq, injected live)
    agent_role      = manifest.policy.proposer_role
    writable_lanes  = manifest.data.declared_lane_kinds.keys.each_with_object([]) do |lane_name, acc|
      next unless agent_role

      verb    = manifest.policy.verb_for_lane(lane_name)
      writers = manifest.policy.roles_with_capability(verb)
      acc << lane_name if writers.include?(agent_role)
    end
    propose_lane = manifest.policy.propose_lane_for(agent_role)
    agent_quickstart = {
      "read_verbs" => Textus::Surface::MCP::Catalog.read_verbs,
      "write_verbs" => agent_role ? Textus::Surface::MCP::Catalog.write_verbs : [],
      "writable_lanes" => writable_lanes,
      "propose_lane" => propose_lane,
    }

    # Agent protocol / recipes (was Boot.agent_protocol)
    queue = manifest.policy.queue_lane
    feeds = manifest.data.declared_lane_kinds.find { |_, k| k == :machine }&.first || "artifacts"
    agent_protocol = {
      "version" => Textus::PROTOCOL,
      "recipes" => {
        "read" => { "purpose" => "find and read an entry",
                    "steps" => ["list (lane:, prefix:, q:, schema:) — discover keys",
                                "get KEY — returns the entry envelope"] },
        "write" => { "purpose" => "create or update an entry",
                     "steps" => ["schema KEY — learn field shape",
                                 "assemble envelope: { _meta: {…}, body: \"…\" }",
                                 "put KEY — persist it (role-gated)"] },
        "propose" => { "purpose" => "agent suggests a change for human review",
                       "agent_steps" => ["propose KEY — writes to #{queue} lane"],
                       "human_steps" => ["accept #{queue}.KEY — promotes to target lane"] },
        "drain" => { "purpose" => "keep machine lanes fresh",
                     "steps" => ["pulse — stale list names overdue entries",
                                 "drain (lane: #{feeds}) — re-pull stale entries"] },
      },
      "role_resolution" => {
        "summary" => "role resolved: --as flag → TEXTUS_ROLE env → .textus/role file → transport default",
        "roles" => manifest.data.role_caps.keys,
        "ref" => "SPEC.md §5",
      },
    }

    {
      "content" => {
        "project" => {
          "name" => project["name"],
          "description" => project["description"],
          "commands" => (project["commands"] || {}).map { |k, v| "- **#{k}**: `#{v}`" }.join("\n"),
          "has_commands" => !(project["commands"] || {}).empty?,
        },
        "runbooks" => runbooks.map { |r| { "name" => r["name"], "description" => r["description"] } },
        "lanes" => lanes,
        "agent_quickstart" => agent_quickstart,
        "agent_protocol" => agent_protocol,
      },
    }
  end

  publish
end
# rubocop:enable Metrics/BlockLength
