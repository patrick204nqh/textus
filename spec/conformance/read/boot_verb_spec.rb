require "spec_helper"

RSpec.describe "boot verb dispatch" do
  include_context "textus_store_fixture"

  before do
    FileUtils.mkdir_p(File.join(root, "data/knowledge"))
    FileUtils.mkdir_p(File.join(root, "schemas"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      lanes:
        - { name: knowledge, kind: canon }
      entries:
        - { key: knowledge.note, path: knowledge/note.md, lane: knowledge, owner: human:self, kind: leaf }
    YAML
    FileUtils.mkdir_p(audit_dir_path(root))
    File.write(audit_log_path(root), "")
  end

  let(:store) { Textus::Store.new(root) }

  it "dispatches store.boot to Read::Boot and returns the contract envelope" do
    res = store.boot
    expect(res["protocol"]).to eq(Textus::PROTOCOL)
    expect(res).to include("lanes", "agent_quickstart")
  end

  it "is reachable via the role-scoped facade" do
    res = store.as("human").boot
    expect(res["store_root"]).to eq(store.root)
  end
end
