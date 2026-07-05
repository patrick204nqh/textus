# Consolidates 5 lane/role doc workflows into one — builds manifest data
# once, publishes to all templates. Replaces:
#   architecture/index.rb  reference/lanes.rb  explanation/concepts.rb
#   how_to/configuring_lanes.rb  how_to/agents_mcp.rb

LOOP_NODES = [
  { "node" => "Intent", "key" => "knowledge.loop.intent" },
  { "node" => "Constraint", "key" => "knowledge.loop.constraint.repo / knowledge.loop.constraint.protocol" },
  { "node" => "Judgment", "key" => "knowledge.loop.judgment.engineering / knowledge.loop.judgment.agent-behavior" },
  { "node" => "Evidence", "key" => "knowledge.loop.evidence" },
  { "node" => "Execution", "key" => "knowledge.loop.execution" },
  { "node" => "Feedback", "key" => "knowledge.loop.feedback" },
].freeze

Textus.workflow "docs-lanes" do
  on "artifacts.docs.lanes", "knowledge.loop.**"
  priority 10

  step :build do |_, ctx|
    kmap = Textus::Manifest::Schema::Vocabulary::LANES
    base_lanes = build_lanes(ctx)
    roles = build_roles(ctx)

    lanes_with_capability = base_lanes.map { |l| l.merge("capability" => kmap[l["kind"]] || "n/a") }
    agent_lanes = base_lanes.select { |l| l["writers"].include?("agent") }
    propose_lane = ctx.manifest.policy.propose_lane_for("agent").to_s
    authority = roles.map do |role|
      writes = base_lanes.each_with_object({}) { |l, h| h[l["name"]] = l["writers"].include?(role["name"]) }
      role.merge("lane_writes" => writes)
    end

    { "content" => {
      "lanes" => lanes_with_capability,
      "roles" => roles,
      "kind_capability_map" => kmap,
      "loop_nodes" => LOOP_NODES,
      "propose_lane" => propose_lane,
      "writable_agent_lanes" => agent_lanes,
      "role_authority" => authority,
    } }
  end

  publish to: "docs/architecture/README.md", template: "docs/architecture/index.erb"
  publish to: "docs/reference/lanes.md", template: "docs/reference/lanes.erb"
  publish to: "docs/explanation/concepts.md", template: "docs/explanation/concepts.erb"
  publish to: "docs/how-to/configuring-lanes.md", template: "docs/how-to/configuring-lanes.erb"
  publish to: "docs/how-to/agents-mcp.md", template: "docs/how-to/agents-mcp.erb"
  publish to: "docs/how-to/drain-scheduling.md", template: "docs/how-to/drain-scheduling.erb"
end
