Textus.workflow "how-to-agents-mcp" do
  match "artifacts.how-to.agents-mcp"

  step :build do |_, ctx|
    data   = ctx.manifest.data
    policy = ctx.manifest.policy

    agent_lanes = lambda do
      data.declared_lane_kinds.filter_map do |name, kind|
        next unless policy.writers_for(name).include?("agent")

        { "name" => name.to_s, "kind" => kind.to_s, "purpose" => data.lane_descs[name].to_s }
      end
    end

    authority = lambda do
      data.role_caps.map do |role, caps|
        writes = data.declared_lane_kinds.each_with_object({}) do |(lane, kind), h|
          _ = kind
          h[lane.to_s] = policy.writers_for(lane).include?(role.to_s)
        end
        { "role" => role.to_s, "capabilities" => caps.map(&:to_s), "lane_writes" => writes }
      end
    end

    propose_lane = policy.propose_lane_for("agent").to_s

    { "content" => { "writable_agent_lanes" => agent_lanes.call,
                     "propose_lane" => propose_lane,
                     "role_authority" => authority.call } }
  end
  publish to: "docs/how-to/agents-mcp.md", template: "docs/how-to/agents-mcp.erb"
end
