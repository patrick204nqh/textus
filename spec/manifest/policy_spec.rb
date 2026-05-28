require "spec_helper"

RSpec.describe Textus::Manifest::Policy do
  subject(:policy) { described_class.new(data) }

  let(:yaml) do
    <<~YAML
      version: textus/3
      roles:
        - { name: human, kind: proposer }
        - { name: builder, kind: generator }
      zones:
        - { name: working, write_policy: [human] }
        - { name: review,  write_policy: [builder] }
      entries:
        - { key: working.notes, path: working/notes.md, zone: working, schema: null, owner: human:self, kind: leaf }
    YAML
  end
  let(:raw) { YAML.safe_load(yaml, aliases: false) }
  let(:data) { Textus::Manifest::Data.parse(raw, root: ".") }

  it "returns Domain::Permission for #permission_for" do
    expect(policy.permission_for("working")).to be_a(Textus::Domain::Permission)
  end

  it "memoises zone_kinds across calls" do
    a = policy.zone_kinds("working")
    b = policy.zone_kinds("working")
    expect(a).to be(b) # same object
  end

  it "raises UsageError on undeclared zone" do
    expect { policy.zone_writers("nope") }.to raise_error(Textus::UsageError)
  end

  it "exposes role_mapping, role_kind, roles_with_kind" do
    expect(policy.role_mapping).to eq("human" => :proposer, "builder" => :generator)
    expect(policy.role_kind("human")).to eq(:proposer)
    expect(policy.roles_with_kind(:generator)).to eq(["builder"])
  end
end
