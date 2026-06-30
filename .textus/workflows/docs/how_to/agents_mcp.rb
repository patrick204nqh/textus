# rubocop:disable Metrics/BlockLength
Textus.workflow "how-to-agents-mcp" do
  match "artifacts.how-to.agents-mcp"

  step :build do |_, ctx|
    data   = ctx.container.manifest.data
    policy = ctx.container.manifest.policy
    kmap   = Textus::Manifest::Schema::Vocabulary::LANES

    agent_lanes = lambda do
      data.declared_lane_kinds.filter_map do |name, kind|
        cap = kmap[kind.to_s]
        next unless cap && policy.roles_with_capability(cap).include?("agent")

        { "name" => name.to_s, "kind" => kind.to_s, "purpose" => data.lane_descs[name].to_s }
      end
    end

    authority = lambda do
      data.role_caps.map do |role, caps|
        writes = data.declared_lane_kinds.each_with_object({}) do |(lane, kind), h|
          cap = kmap[kind.to_s]
          h[lane.to_s] = cap && caps.include?(cap)
        end
        { "role" => role.to_s, "capabilities" => caps.map(&:to_s), "lane_writes" => writes }
      end
    end

    propose_lane = policy.propose_lane_for("agent").to_s

    { "content" => { "writable_agent_lanes" => agent_lanes.call,
                     "propose_lane" => propose_lane,
                     "role_authority" => authority.call } }
  end

  publish
end
# rubocop:enable Metrics/BlockLength
