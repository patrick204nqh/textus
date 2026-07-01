require "spec_helper"

RSpec.describe "surface adapter dispatch parity" do
  include_context "textus_store_fixture"

  let(:store) { minimal_store(root) }

  it "keeps CLI and MCP adapter parity as an explicit seam target" do
    expect(store.ops(:boot)).to be_a(Hash)
    store.entry(:put, key: "knowledge.foo", _meta: {}, body: "parity")
    expect(store.entry(:get, key: "knowledge.foo")).to be_a(Textus::Value::Envelope)
  end

  it "routes CLI and MCP through VerbDispatch" do
    skip "enable when VerbDispatch is wired"
  end
end
