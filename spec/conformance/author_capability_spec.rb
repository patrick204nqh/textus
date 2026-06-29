require "spec_helper"

RSpec.describe "author capability (ADR 0033)" do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(root, lanes: %w[knowledge proposals], manifest: <<~YAML)
      version: textus/4
      roles:
        - { name: human, can: [author, propose] }
        - { name: agent, can: [propose] }
      lanes:
        - { name: knowledge, kind: canon }
        - { name: proposals, kind: queue }
      entries:
        - { key: knowledge.notes, path: knowledge/notes, lane: knowledge, owner: human:self, kind: nested }
        - { key: proposals.notes, path: proposals/notes, lane: proposals, owner: agent:self, kind: nested }
    YAML
  end

  it "lets an author-holder write a canon zone" do
    store.with_role("human").put("knowledge.notes.x", meta: { "name" => "x" }, body: "hi\n")
    expect(store.with_role("human").get("knowledge.notes.x").body).to eq("hi\n")
  end

  it "rejects the retired `accept` capability at load" do
    bad = { "version" => "textus/4",
            "roles" => [{ "name" => "human", "can" => ["accept"] }],
            "lanes" => [{ "name" => "knowledge", "kind" => "canon" }],
            "entries" => [] }
    expect { Textus::Manifest::Schema.validate!(bad) }
      .to raise_error(Textus::BadManifest, /unknown capability 'accept'/)
  end

  it "fails accept/reject with author_held when the role lacks `author`" do
    store.with_role("agent").put("proposals.notes.p1",
                                 meta: { "name" => "p1", "proposal" => { "target_key" => "knowledge.notes.p1", "action" => "put" } },
                                 body: "please add\n")
    expect { store.with_role("agent").accept("proposals.notes.p1") }.to fail_guard_with("author_held")
  end
end
