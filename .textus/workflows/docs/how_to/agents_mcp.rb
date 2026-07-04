Textus.workflow "how-to-agents-mcp" do
  match "artifacts.how-to.agents-mcp"

  step :build do |_, ctx|
    agent_lanes = build_lanes(ctx).select { |l| l["writers"].include?("agent") }
    propose_lane = ctx.manifest.policy.propose_lane_for("agent").to_s
    authority = build_roles(ctx).map do |role|
      writes = build_lanes(ctx).each_with_object({}) { |l, h| h[l["name"]] = l["writers"].include?(role["name"]) }
      role.merge("lane_writes" => writes)
    end

    { "content" => { "writable_agent_lanes" => agent_lanes,
                     "propose_lane" => propose_lane,
                     "role_authority" => authority } }
  end
  publish to: "docs/how-to/agents-mcp.md", template: "docs/how-to/agents-mcp.erb"
end
