require "spec_helper"

RSpec.describe Textus::Domain::Policy::Promote do
  it "accepts known requirements" do
    p = described_class.new(requires: %w[schema_valid accept_authority_signed])
    expect(p.requires).to contain_exactly(:schema_valid, :accept_authority_signed)
  end

  it "rejects unknown requirements" do
    expect do
      described_class.new(requires: ["telepathy"])
    end.to raise_error(Textus::UsageError, /unknown promote requirement/)
  end

  it "exposes a #demands?(:requirement) predicate" do
    p = described_class.new(requires: ["schema_valid"])
    expect(p.demands?(:schema_valid)).to be(true)
    expect(p.demands?(:accept_authority_signed)).to be(false)
  end

  it "accepts the :accept_authority_signed predicate" do
    p = described_class.new(requires: [:accept_authority_signed])
    expect(p.demands?(:accept_authority_signed)).to be true
  end

  it "rejects the dropped :human_accept legacy alias" do
    expect { described_class.new(requires: [:human_accept]) }
      .to raise_error(Textus::UsageError, /unknown promote requirement.*human_accept/)
  end

  it "still rejects unknown predicates" do
    expect { described_class.new(requires: [:made_up]) }
      .to raise_error(Textus::UsageError, /unknown promote requirement/)
  end
end
