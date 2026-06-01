require "spec_helper"

RSpec.describe Textus::Domain::Policy::Predicates::TargetIsCanon do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(root, zones: %w[knowledge notebook], manifest: <<~YAML)
      version: textus/3
      roles:
        - { name: human, can: [author] }
        - { name: agent, can: [keep] }
      zones:
        - { name: knowledge, kind: canon }
        - { name: notebook,  kind: workspace, owner: agent }
      entries:
        - { key: knowledge.notes, path: knowledge/notes, zone: knowledge, owner: human:self, kind: nested }
        - { key: notebook.notes,  path: notebook/notes,  zone: notebook,  owner: agent:self, kind: nested }
    YAML
  end

  def eval_for(target)
    Textus::Domain::Policy::Evaluation.new(
      actor: "human", transition: :accept, origin: "proposals.notes.p1",
      target: target, envelope: nil, manifest: store.container.manifest
    )
  end

  it "passes for a canon target" do
    expect(described_class.new.call(eval_for("knowledge.notes.p1"))).to be true
  end

  it "fails for a workspace target with a reason naming the kind" do
    pred = described_class.new
    expect(pred.call(eval_for("notebook.notes.p1"))).to be false
    expect(pred.reason).to include("workspace").and include("canon")
  end

  it "fails for an unresolvable target" do
    pred = described_class.new
    expect(pred.call(eval_for("ghost.nope.p1"))).to be false
    expect(pred.reason).to include("no declared entry")
  end
end
