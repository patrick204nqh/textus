require "spec_helper"

# Guard: agent-facing recipe steps must never name a deleted verb (fetch_all,
# removed in ADR 0079). Recipes are surfaced under agent_protocol.recipes.
RSpec.describe "Boot recipes name no deleted verbs" do
  include_context "textus_store_fixture"

  before do
    FileUtils.mkdir_p(File.join(root, "zones/intake"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      roles:
        - { name: human,      can: [author, propose] }
        - { name: automation, can: [reconcile] }
      zones:
        - { name: identity, kind: canon, desc: "human-only" }
        - { name: intake,   kind: quarantine }
    YAML
  end

  let(:store) { Textus::Store.new(root) }
  let(:reconcile_recipe) { Textus::Boot.build(container: store.container)["agent_protocol"]["recipes"]["reconcile"] }
  let(:steps_text) { reconcile_recipe["steps"].join("\n") }

  it "the refresh recipe does not call fetch_all" do
    expect(steps_text).not_to include("fetch_all")
  end

  it "the refresh recipe re-pulls stale entries via reconcile" do
    expect(steps_text).to include("reconcile")
  end
end
