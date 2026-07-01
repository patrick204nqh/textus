require "spec_helper"

RSpec.describe "dispatch per-verb handlers" do
  include_context "textus_store_fixture"

  let(:store) { minimal_store(root) }

  before { Textus::Dispatch::HandlerResolver.eager_load! }

  it "routes get through the read concern with a per-verb handler present" do
    expect(defined?(Textus::Dispatch::Handlers::Read::GetHandler)).to eq("constant")

    store.entry(:put, key: "knowledge.foo", _meta: {}, body: "v1")
    env = store.entry(:get, key: "knowledge.foo")
    expect(env).to be_a(Textus::Value::Envelope)
    expect(env.body.to_s.chomp).to eq("v1")
  end

  it "routes put through the write concern with a per-verb handler present" do
    expect(defined?(Textus::Dispatch::Handlers::Write::PutHandler)).to eq("constant")

    result = store.entry(:put, key: "knowledge.foo", _meta: {}, body: "v2")
    expect(result).to be_a(Textus::Value::Envelope)
    expect(store.entry(:get, key: "knowledge.foo").body.to_s.chomp).to eq("v2")
  end

  it "routes list through the read concern with a per-verb handler present" do
    expect(defined?(Textus::Dispatch::Handlers::Read::ListHandler)).to eq("constant")

    rows = store.entry(:list, prefix: "knowledge")
    expect(rows).to be_an(Array)
  end
end
