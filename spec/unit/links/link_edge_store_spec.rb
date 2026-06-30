require "spec_helper"

RSpec.describe Textus::Links::LinkEdgeStore do
  subject(:store) { described_class.new }

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
end
