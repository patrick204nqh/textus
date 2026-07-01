require "spec_helper"

RSpec.describe "dispatch routing" do
  include_context "textus_store_fixture"

  let(:store) { minimal_store(root) }

  before { Textus::Dispatch::HandlerResolver.eager_load! }

  it "routes get through the read concern" do
    store.put(key: "knowledge.foo", _meta: {}, body: "v1")
    env = store.get(key: "knowledge.foo")
    expect(env).to be_a(Textus::Value::Envelope)
    expect(env.body.to_s.chomp).to eq("v1")
  end

  it "routes put through the write concern" do
    result = store.put(key: "knowledge.foo", _meta: {}, body: "v2")
    expect(result).to be_a(Textus::Value::Envelope)
    expect(store.get(key: "knowledge.foo").body.to_s.chomp).to eq("v2")
  end
end
