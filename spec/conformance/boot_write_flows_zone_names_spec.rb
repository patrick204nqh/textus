require "spec_helper"

RSpec.describe "boot write_flows name live zones, not retired ones (ADR 0034)" do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(root, zones: %w[knowledge notebook artifacts proposals],
                              manifest: <<~YAML)
                                version: textus/3
                                roles:
                                  - { name: human,      can: [author, propose] }
                                  - { name: agent,      can: [propose, keep] }
                                  - { name: automation, can: [reconcile] }
                                zones:
                                  - { name: knowledge, kind: canon }
                                  - { name: notebook,  kind: workspace, owner: agent }
                                  - { name: artifacts, kind: machine }
                                  - { name: proposals, kind: queue }
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

  it "names the live queue and machine zone (ADR 0091: quarantine + derived merged into machine)" do
    expect(flows["agent"]).to include("proposals.*")
    expect(flows["automation"]).to include("artifacts")
  end

  it "never emits a retired zone instance name" do
    # `intake` and `output` are retired zone instance names; `intake` is also a
    # valid entry-kind descriptor (ADR 0091) so match only zone-name patterns.
    # `review` and `output` are pure zone-name relics with no other valid use.
    expect(flows.values.join(" ")).not_to match(/\b(?:review|output)\b/)
    # Detect `intake` only when used as a zone name (e.g. "write to intake")
    # not as an entry-kind modifier ("intake artifacts").
    expect(flows.values.join(" ")).not_to match(/\bwrite.*\bintake\b|\bintake\s+zone\b/)
  end
end
