require "spec_helper"

RSpec.describe Textus::Doctor::Check::ProposalTargets do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(root, lanes: %w[knowledge notebook proposals], manifest: <<~YAML)
      version: textus/4
      roles:
        - { name: human, can: [author, propose] }
        - { name: agent, can: [propose, keep] }
      lanes:
        - { name: knowledge, kind: canon }
        - { name: notebook,  kind: workspace, owner: agent }
        - { name: proposals, kind: queue }
      entries:
        - { key: knowledge.notes, path: knowledge/notes, lane: knowledge, owner: human:self, kind: nested }
        - { key: notebook.notes,  path: notebook/notes,  lane: notebook,  owner: agent:self, kind: nested }
        - { key: proposals.notes, path: proposals/notes, lane: proposals, owner: agent:self, kind: nested }
    YAML
  end

  def propose(name, target_key)
    store.with_role("agent").put(key: "proposals.notes.#{name}",
                                 meta: { "name" => name,
                                         "proposal" => { "target_key" => target_key, "action" => "put" },
                                         "_meta" => { "name" => name } },
                                 body: "x\n")
  end

  it "is silent when every proposal targets a canon zone" do
    propose("ok", "knowledge.notes.ok")
    expect(described_class.new(store.container).call).to eq([])
  end

  it "flags a proposal that targets a non-canon zone (warning)" do
    propose("bad", "notebook.notes.bad")
    issues = described_class.new(store.container).call
    row = issues.find { |i| i["code"] == "proposal.target_not_canon" }
    expect(row).not_to be_nil
    expect(row["level"]).to eq("warning")
    expect(row["subject"]).to eq("proposals.notes.bad")
  end

  it "flags a proposal whose target resolves to nothing" do
    propose("ghost", "ghost.nope.x")
    expect(described_class.new(store.container).call.map { |i| i["code"] })
      .to include("proposal.target_unresolved")
  end
end
