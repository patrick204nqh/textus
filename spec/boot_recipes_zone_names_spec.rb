require "spec_helper"

RSpec.describe "boot agent_protocol recipes name live zones (ADR 0034)" do
  include_context "textus_store_fixture"
  include TextusSpecHelpers

  let(:store) do
    store_from_manifest(root, zones: %w[knowledge feeds proposals], manifest: <<~YAML)
      version: textus/3
      roles:
        - { name: human,      can: [author, propose] }
        - { name: agent,      can: [propose] }
        - { name: automation, can: [fetch, build] }
      zones:
        - { name: knowledge, kind: canon }
        - { name: feeds,     kind: quarantine }
        - { name: proposals, kind: queue }
      entries: []
    YAML
  end

  let(:recipes) { Textus::Boot.build(container: store.container)["agent_protocol"]["recipes"] }

  it "keeps the four recipe keys" do
    expect(recipes.keys).to contain_exactly("read", "write", "propose", "fetch")
  end

  it "names the live queue zone in the propose recipe" do
    text = recipes["propose"].values_at("agent_steps", "human_steps").flatten.join(" ")
    expect(text).to include("proposals.KEY")
    expect(text).not_to include("review.KEY")
  end

  it "names the live quarantine zone in the fetch recipe" do
    text = recipes["fetch"]["steps"].join(" ")
    expect(text).to include("--zone=feeds")
    expect(text).not_to include("--zone=intake")
  end
end
