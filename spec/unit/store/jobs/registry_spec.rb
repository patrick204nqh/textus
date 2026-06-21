RSpec.describe Textus::Store::Jobs::Registry do
  it "fetches registered job classes by type" do
    expect(described_class.fetch(:index)).to eq(Textus::Store::Jobs::Index)
    expect(described_class.fetch(:materialize)).to eq(Textus::Store::Jobs::Materialize)
    expect(described_class.fetch(:sweep)).to eq(Textus::Store::Jobs::Sweep)
  end

  it "accepts string type" do
    expect(described_class.fetch("index")).to eq(Textus::Store::Jobs::Index)
  end

  it "raises UnknownJob for unregistered types" do
    expect { described_class.fetch(:nonexistent) }
      .to raise_error(described_class::UnknownJob)
  end

  it "freezes JOBS so no runtime modification" do
    expect(described_class::JOBS).to be_frozen
  end
end
