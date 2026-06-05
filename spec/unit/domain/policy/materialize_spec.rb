require "spec_helper"

RSpec.describe Textus::Domain::Policy::Materialize do
  it "defaults on_change to 'async' when nil is given" do
    m = described_class.new(on_change: nil)
    expect(m.on_change).to eq("async")
  end

  it "accepts 'sync' and stores it as on_change" do
    m = described_class.new(on_change: "sync")
    expect(m.on_change).to eq("sync")
  end

  it "rejects an unknown strategy with BadManifest mentioning on_change" do
    expect { described_class.new(on_change: "later") }
      .to raise_error(Textus::BadManifest, /on_change/)
  end

  describe "#sync?" do
    it "is true when on_change is 'sync'" do
      expect(described_class.new(on_change: "sync").sync?).to be(true)
    end

    it "is false when on_change is 'async'" do
      expect(described_class.new(on_change: "async").sync?).to be(false)
    end
  end
end
