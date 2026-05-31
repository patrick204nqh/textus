require "spec_helper"
require "tmpdir"

RSpec.describe "author capability (ADR 0033)" do
  include_context "textus_store_fixture"
  include TextusSpecHelpers

  let(:store) do
    store_from_manifest(root, zones: %w[knowledge proposals], manifest: <<~YAML)
      version: textus/3
      roles:
        - { name: human, can: [author, propose] }
        - { name: agent, can: [propose] }
      zones:
        - { name: knowledge, kind: canon }
        - { name: proposals, kind: queue }
      entries:
        - { key: knowledge.notes, path: knowledge/notes, zone: knowledge, schema: null, owner: human:self, nested: true, kind: nested }
        - { key: proposals.notes, path: proposals/notes, zone: proposals, schema: null, owner: agent:self, nested: true, kind: nested }
    YAML
  end

  it "lets an author-holder write a canon zone" do
    store.as("human").put("knowledge.notes.x", meta: { "name" => "x" }, body: "hi\n")
    expect(store.as("human").get("knowledge.notes.x").body).to eq("hi\n")
  end

  it "rejects the retired `accept` capability at load" do
    bad = { "version" => "textus/3",
            "roles" => [{ "name" => "human", "can" => ["accept"] }],
            "zones" => [{ "name" => "knowledge", "kind" => "canon" }] }
    expect { Textus::Manifest::Schema.validate!(bad) }
      .to raise_error(Textus::BadManifest, /unknown capability 'accept'/)
  end

  it "fails accept/reject with author_signed when the role lacks `author`" do
    store.as("agent").put("proposals.notes.p1",
                          meta: { "name" => "p1", "proposal" => { "target_key" => "knowledge.notes.p1", "action" => "put" } },
                          body: "please add\n")
    expect { store.as("agent").accept("proposals.notes.p1") }.to fail_guard_with("author_signed")
  end
end
