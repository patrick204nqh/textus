require "spec_helper"

RSpec.describe "boot verb dispatch" do
  include_context "textus_store_fixture"

  before do
    FileUtils.mkdir_p(File.join(root, "zones/working"))
    FileUtils.mkdir_p(File.join(root, "schemas"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: working, kind: canon }
      entries:
        - { key: working.note, path: working/note.md, zone: working, schema: null, owner: human:self, kind: leaf }
    YAML
    File.write(File.join(root, "audit.log"), "")
  end

  let(:store) { Textus::Store.new(root) }

  it "dispatches store.boot to Read::Boot and returns the contract envelope" do
    res = store.boot
    expect(res["protocol"]).to eq(Textus::PROTOCOL)
    expect(res).to include("zones", "entries", "agent_quickstart", "cli_verbs")
  end

  it "is reachable via the role-scoped facade" do
    res = store.as("human").boot
    expect(res["store_root"]).to eq(store.root)
  end
end
