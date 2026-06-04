require "spec_helper"

RSpec.describe Textus::Domain::Duration do
  it "returns nil for nil" do
    expect(described_class.seconds(nil)).to be_nil
  end

  it "parses bare integer seconds" do
    expect(described_class.seconds("90")).to eq(90)
    expect(described_class.seconds(90)).to eq(90)
  end

  it "parses s/m/h/d suffixes" do
    expect(described_class.seconds("30s")).to eq(30)
    expect(described_class.seconds("5m")).to eq(300)
    expect(described_class.seconds("2h")).to eq(7200)
    expect(described_class.seconds("3d")).to eq(259_200)
  end

  it "returns nil for an unparseable value" do
    expect(described_class.seconds("soon")).to be_nil
  end
end
