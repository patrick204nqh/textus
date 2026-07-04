# rubocop:disable Metrics/BlockLength
Textus.workflow "boot" do
  match "artifacts.boot"

  step :build do |_, ctx|
    manifest = ctx.manifest

    read_family = lambda do |prefix|
      manifest.resolver.enumerate(prefix: prefix, include_keyless: true)
              .reject { |row| row[:key] == prefix }
              .sort_by { |row| row[:key] }
              .filter_map { |row| ctx.read(row[:key]) }
    end

    fetch = ->(key) { ctx.read(key) }

    # Project context (was artifacts.config.orientation)
    identity_env = fetch.call("knowledge.loop.intent.0003-identity")
    identity = identity_env&.meta || {}

    runbooks = read_family.call("knowledge.loop.execution").filter_map do |env|
      m = env.meta
      next unless m
      m.merge("schema" => env.schema_ref)
    end

    loop_nodes = %w[intent constraint.repo constraint.protocol judgment.engineering
                    judgment.agent-behavior evidence execution feedback]
    agent_behavior_excerpt = fetch.call("knowledge.loop.judgment.agent-behavior.0001-loop-behavior")&.body.to_s
    loop_summary = {
      "nodes" => loop_nodes,
      "excerpt" => agent_behavior_excerpt.lines.first(5).join,
    }

    # Lanes (was Boot.lanes_for)
    lanes = manifest.data.declared_lane_kinds.keys.map do |name|
      row  = { "name" => name, "writers" => manifest.policy.writers_for(name) }
      kind = manifest.data.declared_lane_kinds[name]
      row["kind"] = kind.to_s if kind
      desc = manifest.data.lane_descs[name]
      row["purpose"] = desc if desc && !desc.empty?
      row
    end

    # Agent quickstart (was Boot.agent_quickstart — minus latest_seq, injected live)
    agent_role      = manifest.policy.proposer_role
    writable_lanes  = manifest.data.declared_lane_kinds.keys.each_with_object([]) do |lane_name, acc|
      next unless agent_role

      writers = manifest.policy.writers_for(lane_name)
      acc << lane_name if writers.include?(agent_role)
    end
    propose_lane = manifest.policy.propose_lane_for(agent_role)
    read_verbs = Textus::Protocol::VerbRegistry.registered.select { |s| s.read? && s.mcp? }.map { |s| s.verb.to_s }
    write_verbs = if agent_role
                    Textus::Protocol::VerbRegistry.registered.select { |s| s.write? && s.mcp? }.map { |s| s.verb.to_s }
                  else
                    []
                  end
    agent_quickstart = {
      "read_verbs" => read_verbs,
      "write_verbs" => write_verbs,
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
          "name" => identity["name"],
          "description" => identity["description"],
          "commands" => (identity["commands"] || {}).map { |k, v| "- **#{k}**: `#{v}`" }.join("\n"),
          "has_commands" => !(identity["commands"] || {}).empty?,
        },
        "runbooks" => runbooks.map { |r| { "name" => r["name"], "description" => r["description"], "schema" => r["schema"] } },
        "loop" => loop_summary,
        "lanes" => lanes,
        "agent_quickstart" => agent_quickstart,
        "agent_protocol" => agent_protocol,
      },
    }
  end
  publish to: "CLAUDE.md", template: "docs/meta/orientation.erb", inject_boot: true
  publish to: "AGENTS.md", template: "docs/meta/orientation.erb", inject_boot: true
end
# rubocop:enable Metrics/BlockLength
