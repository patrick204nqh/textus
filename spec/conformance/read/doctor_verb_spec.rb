require "spec_helper"

RSpec.describe "doctor verb dispatch" do
  include_context "textus_store_fixture"

  before do
    FileUtils.mkdir_p(File.join(root, "data/knowledge"))
    FileUtils.mkdir_p(File.join(root, "schemas"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/4
      lanes:
        - { name: knowledge, kind: canon }
      entries:
        - { key: knowledge.note, path: knowledge/note.md, lane: knowledge, owner: human:self, kind: leaf }
    YAML
    FileUtils.mkdir_p(audit_dir_path(root))
    File.write(audit_log_path(root), "")
  end

  let(:store) { Textus::Store.new(root) }

  it "dispatches store.doctor to DoctorStore and returns the report envelope" do
    res = store.doctor
    expect(res["protocol"]).to eq(Textus::PROTOCOL)
    expect(res).to have_key("ok")
    expect(res).to have_key("issues")
    expect(res).to have_key("summary")
  end

  it "forwards the checks: filter through the verb" do
    res = store.with_role("human").doctor(checks: ["protocol_version"])
    expect(res).to have_key("issues")
  end

  it "raises on an unknown check (delegated to Doctor.build)" do
    expect { store.doctor(checks: ["nope"]) }.to raise_error(Textus::UsageError, /unknown doctor check/)
  end
end
