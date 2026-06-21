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
    spec = Textus::Action::Get.contract
    result = gate.dispatch(spec: spec, inputs: { key: "knowledge.note" }, role: "human")
    expect(result).not_to be_nil
    expect(result.to_h_for_wire["key"]).to eq("knowledge.note")
  end

  it "dispatches List" do
    spec = Textus::Action::List.contract
    result = gate.dispatch(spec: spec, inputs: { prefix: nil, lane: nil }, role: "human")
    expect(result).to be_an(Array)
  end

  it "raises UsageError for unknown verb" do
    bad_spec = Textus::Contract::Spec.new(verb: :nonexistent, args: [], surfaces: [], views: { default: lambda { |v, _|
      v
    } }, cli: nil, cli_stdin: nil, summary: nil)
    expect { gate.dispatch(spec: bad_spec, inputs: {}, role: "human") }.to raise_error(Textus::UsageError, /unknown command verb/)
  end
end
