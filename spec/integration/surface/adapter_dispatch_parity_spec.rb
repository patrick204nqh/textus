require "spec_helper"

RSpec.describe "surface adapter dispatch parity" do
  include_context "textus_store_fixture"

  let(:store) { minimal_store(root) }

  it "keeps CLI and MCP adapter parity as an explicit seam target" do
    expect(store.boot).to be_a(Hash)
    store.put(key: "knowledge.foo", _meta: {}, body: "parity")
    expect(store.get(key: "knowledge.foo")).to be_a(Textus::Value::Envelope)
  end

  it "routes CLI and MCP through unified store dispatch" do
    expect(store.list(prefix: "knowledge")).to be_an(Array)
    result = Textus::Surface::MCP::Projector.new.dispatch(:list, inputs: {}, store: store)
    expect(result).to be_an(Array)
  end
end
