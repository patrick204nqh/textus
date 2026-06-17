require "spec_helper"

RSpec.describe "Manifest::Data drops the vestigial #zones map (ADR 0034 / D2)" do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(root, lanes: %w[knowledge proposals], manifest: <<~YAML)
      version: textus/4
      roles: [{ name: human, can: [author, propose] }]
      lanes:
        - { name: knowledge, kind: canon }
        - { name: proposals, kind: queue }
      entries: []
    YAML
  end

  it "no longer responds to #zones" do
    expect(store.container.manifest.data).not_to respond_to(:lanes)
  end

  it "exposes declared zone names through declared_lane_kinds" do
    expect(store.container.manifest.data.declared_lane_kinds.keys).to contain_exactly("knowledge", "proposals")
  end
end
