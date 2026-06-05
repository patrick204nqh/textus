require "spec_helper"

RSpec.describe Textus::Manifest::Data do
  subject(:data) { described_class.parse(raw, root: "/tmp/store") }

  let(:yaml) do
    <<~YAML
      version: textus/3
      roles:
        - { name: human, can: [author, propose] }
        - { name: automation, can: [reconcile] }
      zones:
        - { name: knowledge, kind: canon }
        - { name: review,  kind: derived }
      entries:
        - { key: knowledge.notes, path: knowledge/notes.md, zone: knowledge, owner: human:self, kind: leaf }
    YAML
  end
  let(:raw) { YAML.safe_load(yaml, aliases: false) }

  it "exposes zones, entries, audit_config, role_caps" do
    expect(data.declared_zone_kinds).to be_a(Hash)
    expect(data.entries).to all(be_a(Textus::Manifest::Entry::Base))
    expect(data.audit_config).to include(:max_size, :keep)
    expect(data.role_caps).to eq("human" => %w[author propose], "automation" => %w[reconcile])
  end

  it "derives zone writers from capability × zone-kind" do
    expect(data.policy.zone_writers("knowledge")).to eq(["human"])
    expect(data.policy.zone_writers("review")).to eq(["automation"])
  end

  it "exposes roles holding a capability" do
    expect(data.policy.roles_with_capability("author")).to eq(["human"])
    expect(data.policy.roles_with_capability("reconcile")).to eq(["automation"])
  end

  it "exposes raw and root" do
    expect(data.raw).to eq(raw)
    expect(data.root).to eq("/tmp/store")
  end

  it "is frozen after parse (no behavioural state)" do
    expect(data).to be_frozen
  end
end
