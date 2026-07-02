LOOP_NODES = [
  { "node" => "Intent", "key" => "knowledge.intent" },
  { "node" => "Constraint", "key" => "knowledge.constraint.repo / knowledge.constraint.protocol" },
  { "node" => "Judgment", "key" => "knowledge.judgment.engineering / knowledge.judgment.agent-behavior" },
  { "node" => "Evidence", "key" => "knowledge.evidence" },
  { "node" => "Execution", "key" => "knowledge.execution" },
  { "node" => "Feedback", "key" => "knowledge.feedback" },
].freeze

Textus.workflow "explanation-concepts" do
  match "artifacts.explanation.concepts"

  step :build do |_, ctx|
    data   = ctx.container.manifest.data
    policy = ctx.container.manifest.policy
    kmap   = Textus::Manifest::Schema::Vocabulary::LANES

    lanes = data.declared_lane_kinds.map do |name, kind|
      cap     = kmap[kind.to_s]
      writers = cap ? policy.roles_with_capability(cap).map(&:to_s) : []
      { "name" => name.to_s, "kind" => kind.to_s,
        "purpose" => data.lane_descs[name].to_s, "capability" => cap.to_s, "writers" => writers }
    end

    roles = data.role_caps.map do |role, caps|
      { "name" => role.to_s, "capabilities" => caps.map(&:to_s) }
    end

    propose_lane = policy.propose_lane_for("agent").to_s

    {
      "content" => {
        "lanes" => lanes,
        "roles" => roles,
        "loop_nodes" => LOOP_NODES,
        "propose_lane" => propose_lane,
      },
    }
  end
  publish to: "docs/explanation/concepts.md", template: "docs/explanation/concepts.erb"
end
