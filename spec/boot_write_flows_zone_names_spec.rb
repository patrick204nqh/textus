require "spec_helper"

RSpec.describe "boot write_flows name live zones, not retired ones (ADR 0034)" do
  include_context "textus_store_fixture"
  include TextusSpecHelpers

  let(:store) do
    store_from_manifest(root, zones: %w[knowledge notebook feeds proposals artifacts],
                              manifest: <<~YAML)
                                version: textus/3
                                roles:
                                  - { name: human,      can: [author, propose] }
                                  - { name: agent,      can: [propose, keep] }
                                  - { name: automation, can: [fetch, build] }
                                zones:
                                  - { name: knowledge, kind: canon }
                                  - { name: notebook,  kind: workspace, owner: agent }
                                  - { name: feeds,     kind: quarantine }
                                  - { name: proposals, kind: queue }
                                  - { name: artifacts, kind: derived }
                                entries: []
                              YAML
  end

  let(:flows) { Textus::Boot.build(container: store.container)["write_flows"] }

  it "names the live canon zone in the author flow" do
    expect(flows["human"]).to include("knowledge")
    expect(flows["human"]).not_to include("identity")
    expect(flows["human"]).not_to include("working")
  end

  it "emits a notebook write-flow for the keep-holder (the 0.33 gap)" do
    expect(flows["agent"]).to include("notebook")
    expect(flows["agent"]).to include("no accept needed")
  end

  it "names the live queue, quarantine, and derived zones" do
    expect(flows["agent"]).to include("proposals.*")
    expect(flows["automation"]).to include("feeds")
    expect(flows["automation"]).to include("artifacts")
  end

  it "never emits a retired zone instance name" do
    expect(flows.values.join(" ")).not_to match(/\b(?:review|intake|output)\b/)
  end
end
