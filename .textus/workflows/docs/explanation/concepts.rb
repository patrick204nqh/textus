LOOP_NODES = [
  { "node" => "Intent", "key" => "knowledge.loop.intent" },
  { "node" => "Constraint", "key" => "knowledge.loop.constraint.repo / knowledge.loop.constraint.protocol" },
  { "node" => "Judgment", "key" => "knowledge.loop.judgment.engineering / knowledge.loop.judgment.agent-behavior" },
  { "node" => "Evidence", "key" => "knowledge.loop.evidence" },
  { "node" => "Execution", "key" => "knowledge.loop.execution" },
  { "node" => "Feedback", "key" => "knowledge.loop.feedback" },
].freeze

Textus.workflow "explanation-concepts" do
  on "artifacts.explanation.concepts"

  step :build do |_, ctx|
    kmap  = Textus::Manifest::Schema::Vocabulary::LANES
    lanes = build_lanes(ctx).map { |l| l.merge("capability" => kmap[l["kind"]].to_s) }
    roles = build_roles(ctx)
    propose_lane = ctx.manifest.policy.propose_lane_for("agent").to_s

    { "content" => { "lanes" => lanes, "roles" => roles,
                     "loop_nodes" => LOOP_NODES, "propose_lane" => propose_lane } }
  end
  publish to: "docs/explanation/concepts.md", template: "docs/explanation/concepts.erb"
end
