require "spec_helper"

# Guard: agent-facing write-flow guidance must never name a verb that the
# dispatcher no longer registers (fetch/fetch_all removed in ADR 0079).
RSpec.describe "Boot write-flows name no deleted verbs" do
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
  let(:automation_flow) { Textus::Boot.build(container: store.container)["write_flows"]["automation"] }

  it "the automation write-flow does not invoke 'textus fetch'" do
    expect(automation_flow).not_to include("textus fetch")
  end

  it "the automation write-flow points at reconcile for quarantine refresh" do
    expect(automation_flow).to include("textus reconcile")
  end
end
