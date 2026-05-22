require "spec_helper"

RSpec.describe Textus::Domain::Policy::Promote do
  it "accepts known requirements" do
    p = described_class.new(requires: %w[schema_valid human_accept])
    expect(p.requires).to contain_exactly(:schema_valid, :human_accept)
  end

  it "rejects unknown requirements" do
    expect do
      described_class.new(requires: ["telepathy"])
    end.to raise_error(Textus::UsageError, /unknown promote requirement/)
  end

  it "exposes a #demands?(:requirement) predicate" do
    p = described_class.new(requires: ["schema_valid"])
    expect(p.demands?(:schema_valid)).to be(true)
    expect(p.demands?(:human_accept)).to be(false)
  end
end
