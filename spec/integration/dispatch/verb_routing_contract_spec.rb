require "spec_helper"

RSpec.describe "verb routing contract" do
  include_context "textus_store_fixture"

  let(:store) { minimal_store(root) }

  it "keeps get/list/put reachable through unified dispatch" do
    expect { store.list(prefix: "knowledge") }.not_to raise_error
    expect { store.put(key: "knowledge.foo", _meta: {}, body: "updated") }.not_to raise_error
    expect { store.get(key: "knowledge.foo") }.not_to raise_error
  end

  it "routes every verb through method_missing" do
    expect(store).to respond_to(:list)
    expect(store).to respond_to(:get)
    expect(store).to respond_to(:put)
  end
end
