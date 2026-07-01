require "spec_helper"
require "tmpdir"

RSpec.describe Textus::Links::LinkEdgeStore do
  let(:tmp) { Dir.mktmpdir }
  let(:db)  { Textus::Port::Store.new(root: File.join(tmp, ".textus")).setup! }

  after { db.close; FileUtils.rm_rf(tmp) }

  subject(:store) { described_class.new(db:) }

  it "records a link from source to target key" do
    store.record(from_key: "artifacts.how-to.guide", to_key: "artifacts.reference.lanes")
    expect(store.dependents_of("artifacts.reference.lanes")).to contain_exactly("artifacts.how-to.guide")
  end

  it "returns empty array for a key with no link dependents" do
    expect(store.dependents_of("artifacts.reference.lanes")).to eq([])
  end

  it "handles multiple sources pointing to the same target" do
    store.record(from_key: "artifacts.how-to.a", to_key: "artifacts.reference.lanes")
    store.record(from_key: "artifacts.how-to.b", to_key: "artifacts.reference.lanes")
    expect(store.dependents_of("artifacts.reference.lanes")).to contain_exactly(
      "artifacts.how-to.a", "artifacts.how-to.b"
    )
  end

  it "deduplicates repeated records of the same edge" do
    store.record(from_key: "artifacts.how-to.a", to_key: "artifacts.reference.lanes")
    store.record(from_key: "artifacts.how-to.a", to_key: "artifacts.reference.lanes")
    expect(store.dependents_of("artifacts.reference.lanes").length).to eq(1)
  end

  it "returns neighbors for a key with outgoing and incoming edges" do
    store.record(from_key: "knowledge.a", to_key: "knowledge.b")
    store.record(from_key: "knowledge.c", to_key: "knowledge.a")
    expect(store.neighbors_of("knowledge.a")).to contain_exactly("knowledge.b", "knowledge.c")
  end

  it "returns reachable keys with depth limit" do
    store.record(from_key: "knowledge.a", to_key: "knowledge.b")
    store.record(from_key: "knowledge.b", to_key: "knowledge.c")
    store.record(from_key: "knowledge.c", to_key: "knowledge.d")
    expect(store.reachable("knowledge.a", depth: 2)).to contain_exactly("knowledge.b", "knowledge.c")
    expect(store.reachable("knowledge.a", depth: 3)).to contain_exactly("knowledge.b", "knowledge.c", "knowledge.d")
  end

  it "returns all reachable keys without depth limit" do
    store.record(from_key: "knowledge.a", to_key: "knowledge.b")
    store.record(from_key: "knowledge.b", to_key: "knowledge.c")
    expect(store.reachable("knowledge.a")).to contain_exactly("knowledge.b", "knowledge.c")
  end
end
