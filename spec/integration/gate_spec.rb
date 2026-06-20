# spec/integration/gate_spec.rb
require "spec_helper"

RSpec.describe Textus::Gate do
  include_context "textus_store_fixture"

  before do
    FileUtils.mkdir_p(File.join(root, "data/knowledge"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/4
      lanes:
        - { name: knowledge, kind: canon }
      entries:
        - { key: knowledge.note, path: knowledge/note.md, lane: knowledge, kind: leaf }
    YAML
    File.write(File.join(root, "data/knowledge/note.md"), "---\nuid: abc\n---\nhello\n")
  end

  let(:store)     { Textus::Store.new(root) }
  let(:container) { store.container }
  let(:gate)      { Textus::Gate.new(container) }

  it "dispatches Get and returns the envelope" do
    cmd = Textus::Command.new(verb: :get, params: { key: "knowledge.note" }, role: "human")
    result = gate.dispatch(cmd)
    expect(result).not_to be_nil
    expect(result.to_h_for_wire["key"]).to eq("knowledge.note")
  end

  it "dispatches List" do
    cmd = Textus::Command.new(verb: :list, params: { prefix: nil, lane: nil }, role: "human")
    result = gate.dispatch(cmd)
    expect(result).to be_an(Array)
  end

  it "raises UsageError for unknown verb" do
    cmd = Textus::Command.new(verb: :nonexistent, params: {}, role: "human")
    expect { gate.dispatch(cmd) }.to raise_error(Textus::UsageError, /unknown command verb/)
  end
end
