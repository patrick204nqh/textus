RSpec.describe Textus::Protocol::VerbRegistry::VerbSpec do
  it "accepts lane: keyword" do
    spec = described_class.new(
      verb: :ingest, summary: "desc", args: [],
      surfaces: %i[cli mcp], category: :write,
      lane: :ingest
    )
    expect(spec.lane).to eq(:ingest)
  end

  it "defaults lane to nil" do
    spec = described_class.new(
      verb: :get, summary: "desc", args: [],
      surfaces: %i[cli mcp], category: :read
    )
    expect(spec.lane).to be_nil
  end

  it "raises on unknown keyword" do
    expect do
      described_class.new(
        verb: :x, summary: "desc", args: [],
        surfaces: [], category: :read,
        bad: 1
      )
    end.to raise_error(ArgumentError)
  end
end
