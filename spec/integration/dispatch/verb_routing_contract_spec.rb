require "spec_helper"

RSpec.describe "verb routing contract" do
  include_context "textus_store_fixture"

  let(:store) { minimal_store(root) }

  it "keeps get/list/put reachable through the current entry interface" do
    expect { store.entry(:list, prefix: "knowledge") }.not_to raise_error
    expect { store.entry(:put, key: "knowledge.foo", _meta: {}, body: "updated") }.not_to raise_error
    expect { store.entry(:get, key: "knowledge.foo") }.not_to raise_error
  end

  it "marks the future verb dispatch seam explicitly" do
    expect(defined?(Textus::Dispatch::VerbDispatch)).to eq("constant")
  end
end
