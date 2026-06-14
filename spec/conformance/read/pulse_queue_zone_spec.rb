require "spec_helper"

RSpec.describe "pulse pending_review derives the queue zone, not 'review' (ADR 0034 / D1)" do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(root, lanes: %w[knowledge proposals], manifest: <<~YAML)
      version: textus/3
      roles:
        - { name: human, can: [author] }
        - { name: agent, can: [propose] }
      lanes:
        - { name: knowledge, kind: canon }
        - { name: proposals, kind: queue }
      entries:
        - { key: proposals.p1, path: data/proposals/p1.md, lane: proposals, owner: agent:self, kind: leaf }
    YAML
  end

  it "lists keys from the live queue zone (named 'proposals', not 'review')" do
    store.as("agent").put("proposals.p1",
                          meta: { "name" => "p1", "proposal" => { "target_key" => "knowledge.p1", "action" => "put" } },
                          body: "please add\n")
    pulse = store.as("agent").pulse
    expect(pulse["pending_review"]).to include("proposals.p1")
  end

  it "returns [] cleanly when no queue zone is declared" do
    s = store_from_manifest(File.join(tmp, "no-queue", ".textus"), lanes: %w[knowledge], manifest: <<~YAML)
      version: textus/3
      roles: [{ name: human, can: [author] }]
      lanes: [{ name: knowledge, kind: canon }]
      entries: []
    YAML
    expect(s.as("human").pulse["pending_review"]).to eq([])
  end
end
