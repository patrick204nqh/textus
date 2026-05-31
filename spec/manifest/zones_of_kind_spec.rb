require "spec_helper"

RSpec.describe "Manifest::Policy#zones_of_kind (ADR 0034)" do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(root, zones: %w[knowledge notebook feeds], manifest: <<~YAML)
      version: textus/3
      roles:
        - { name: human,      can: [author] }
        - { name: agent,      can: [keep] }
        - { name: automation, can: [fetch] }
      zones:
        - { name: knowledge, kind: canon }
        - { name: notebook,  kind: workspace, owner: agent }
        - { name: feeds,     kind: quarantine }
      entries: []
    YAML
  end

  let(:policy) { store.container.manifest.policy }

  it "returns the zone names declaring a given kind, in manifest order" do
    expect(policy.zones_of_kind(:canon)).to eq(["knowledge"])
    expect(policy.zones_of_kind(:workspace)).to eq(["notebook"])
    expect(policy.zones_of_kind(:quarantine)).to eq(["feeds"])
  end

  it "returns [] for a kind no zone declares" do
    expect(policy.zones_of_kind(:derived)).to eq([])
  end
end
