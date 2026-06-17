require "spec_helper"

RSpec.describe "workspace lane-kind + keep capability (ADR 0033)" do
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
        - { key: notebook.notes, path: notebook/notes, lane: notebook, owner: agent:self, kind: nested }
    YAML
  end

  it "lets a keep-holder write its workspace directly — no accept needed (closes the agent-memory gap)" do
    store.as("agent").put("notebook.notes.session1", meta: { "name" => "session1" }, body: "learned X\n")
    expect(store.as("agent").get("notebook.notes.session1").body).to eq("learned X\n")
  end

  it "refuses a role that lacks the keep capability" do
    expect do
      store.as("human").put("notebook.notes.x", meta: { "name" => "x" }, body: "")
    end.to raise_error(Textus::WriteForbidden, /capability 'keep'/)
  end

  it "requires some role to hold keep when a workspace lane is declared" do
    bad = { "version" => "textus/4",
            "roles" => [{ "name" => "human", "can" => ["author"] }],
            "lanes" => [{ "name" => "notebook", "kind" => "workspace" }],
            "entries" => [] }
    expect { Textus::Manifest::Schema.validate!(bad) }
      .to raise_error(Textus::BadManifest, /needs a role with capability 'keep'/)
  end
end
