require "spec_helper"

RSpec.describe "doctor verb dispatch" do
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

  it "dispatches store.doctor to Read::Doctor and returns the report envelope" do
    res = store.doctor
    expect(res["protocol"]).to eq(Textus::PROTOCOL)
    expect(res).to have_key("ok")
    expect(res).to have_key("issues")
    expect(res).to have_key("summary")
  end

  it "forwards the checks: filter through the verb" do
    res = store.as("human").doctor(checks: ["protocol_version"])
    expect(res).to have_key("issues")
  end

  it "raises on an unknown check (delegated to Doctor.build)" do
    expect { store.doctor(checks: ["nope"]) }.to raise_error(Textus::UsageError, /unknown doctor check/)
  end
end
