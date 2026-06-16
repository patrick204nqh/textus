require "spec_helper"

RSpec.describe "accept refuses a non-canon proposal target (ADR 0035)" do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(root, lanes: %w[knowledge notebook proposals], manifest: <<~YAML)
      version: textus/3
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

  def propose(target_key)
    store.as("agent").put("proposals.notes.p1",
                          meta: { "name" => "p1",
                                  "proposal" => { "target_key" => target_key, "action" => "put" },
                                  "_meta" => { "name" => "p1" } },
                          body: "please add\n")
  end

  it "accepts a proposal targeting a canon zone" do
    propose("knowledge.notes.p1")
    result = store.as("human").accept("proposals.notes.p1")
    expect(result["accepted"]).to eq("proposals.notes.p1")
    expect(result["target_key"]).to eq("knowledge.notes.p1")
  end

  it "refuses a proposal whose target resolves to no declared entry" do
    propose("ghost.nope.p1")
    expect { store.as("human").accept("proposals.notes.p1") }.to raise_error(Textus::UnknownKey)
  end
end
