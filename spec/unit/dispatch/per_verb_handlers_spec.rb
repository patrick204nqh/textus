require "spec_helper"

RSpec.describe "dispatch per-verb handlers" do
  include_context "textus_store_fixture"

  let(:store) { minimal_store(root) }
  let(:mv_store) do
    store_from_manifest(root, lanes: ["knowledge"], manifest: <<~YAML)
      version: textus/4
      lanes:
        - { name: knowledge, kind: canon }
      entries:
        - { key: knowledge.foo, path: knowledge/foo.md, lane: knowledge, kind: leaf }
        - { key: knowledge.moved, path: knowledge/moved.md, lane: knowledge, kind: leaf }
    YAML
  end

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

  it "routes key_mv through the write concern with a per-verb handler present" do
    expect(defined?(Textus::Dispatch::Handlers::Write::MoveKeyHandler)).to eq("constant")

    mv_store.entry(:put, key: "knowledge.foo", _meta: {}, body: "mv")
    result = mv_store.entry(:key_mv, old_key: "knowledge.foo", new_key: "knowledge.moved", if_etag: nil, dry_run: false)

    expect(result).to be_a(Hash)
    expect(result["to_key"]).to eq("knowledge.moved")
    expect(mv_store.entry(:get, key: "knowledge.moved").body.to_s.chomp).to eq("mv")
  end

  it "routes key_delete through the write concern with a per-verb handler present" do
    expect(defined?(Textus::Dispatch::Handlers::Write::DeleteKeyHandler)).to eq("constant")

    store.entry(:put, key: "knowledge.foo", _meta: {}, body: "delete")
    result = store.entry(:key_delete, key: "knowledge.foo", if_etag: nil)

    expect(result).to be_a(Hash)
    expect(result["deleted"]).to be(true)
    expect { store.entry(:get, key: "knowledge.foo") }.to raise_error(Textus::ActionError)
  end

  it "routes data_mv through the write concern with a per-verb handler present" do
    expect(defined?(Textus::Dispatch::Handlers::Write::DataMvHandler)).to eq("constant")

    result = store.ops(:data_mv, from: "knowledge", to: "knowledge_renamed", dry_run: true)
    expect(result).to be_a(Textus::Store::Jobs::Plan)
    expect(result.steps.first["op"]).to eq("rename_zone")
  end
end
