require "spec_helper"

RSpec.describe Textus::Manifest::Data do
  subject(:data) { described_class.parse(raw, root: "/tmp/store") }

  let(:yaml) do
    <<~YAML
      version: textus/3
      roles:
        - { name: human, kind: proposer }
        - { name: builder, kind: generator }
      zones:
        - { name: working, kind: origin, write_policy: [human] }
        - { name: review,  kind: derived, write_policy: [builder] }
      entries:
        - { key: working.notes, path: working/notes.md, zone: working, schema: null, owner: human:self, kind: leaf }
    YAML
  end
  let(:raw) { YAML.safe_load(yaml, aliases: false) }

  it "exposes zones, zone_readers, entries, audit_config, role_mapping" do
    expect(data.zones).to be_a(Hash)
    expect(data.zone_readers).to be_a(Hash)
    expect(data.entries).to all(be_a(Textus::Manifest::Entry::Base))
    expect(data.audit_config).to include(:max_size, :keep)
    expect(data.role_mapping).to be_a(Hash)
  end

  it "exposes raw and root" do
    expect(data.raw).to eq(raw)
    expect(data.root).to eq("/tmp/store")
  end

  it "is frozen after parse (no behavioural state)" do
    expect(data).to be_frozen
  end
end
