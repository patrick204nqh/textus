require "spec_helper"

RSpec.describe Textus::Manifest::Data do
  subject(:data) { described_class.parse(raw, root: "/tmp/store") }

  let(:yaml) do
    <<~YAML
      version: textus/3
      roles:
        - { name: human, can: [author, propose] }
        - { name: automation, can: [converge] }
      lanes:
        - { name: knowledge, kind: canon }
        - { name: review,  kind: machine }
      entries:
        - { key: knowledge.notes, path: data/knowledge/notes.md, lane: knowledge, owner: human:self, kind: leaf }
    YAML
  end
  let(:raw) { YAML.safe_load(yaml, aliases: false) }

  it "exposes zones, entries, audit_config, role_caps" do
    expect(data.declared_lane_kinds).to be_a(Hash)
    expect(data.entries).to all(be_a(Textus::Manifest::Entry::Base))
    expect(data.audit_config).to include(:max_size, :keep)
    expect(data.role_caps).to eq("human" => %w[author propose], "automation" => %w[converge])
  end

  it "derives lane writers from capability x lane-kind" do
    expect(data.policy.roles_with_capability(data.policy.verb_for_lane("knowledge"))).to eq(["human"])
    expect(data.policy.roles_with_capability(data.policy.verb_for_lane("review"))).to eq(["automation"])
  end

  it "exposes roles holding a capability" do
    expect(data.policy.roles_with_capability("author")).to eq(["human"])
    expect(data.policy.roles_with_capability("converge")).to eq(["automation"])
  end

  it "exposes raw and root" do
    expect(data.raw).to eq(raw)
    expect(data.root).to eq("/tmp/store")
  end

  it "is frozen after parse (no behavioural state)" do
    expect(data).to be_frozen
  end
end
