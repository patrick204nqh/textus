require "spec_helper"

RSpec.describe Textus::Domain::Policy::Retention do
  it "exposes parsed windows in seconds" do
    r = described_class.new(expire_after: "30d", archive_after: "7d")
    expect(r.expire_after).to eq(2_592_000)
    expect(r.archive_after).to eq(604_800)
  end

  it "returns :expire when age exceeds expire_after" do
    r = described_class.new(expire_after: "1d")
    expect(r.action_for(86_401)).to eq(:expire)
    expect(r.action_for(86_399)).to be_nil
  end

  it "returns :archive when age exceeds archive_after but not expire_after" do
    r = described_class.new(expire_after: "30d", archive_after: "7d")
    expect(r.action_for(604_801)).to eq(:archive)
  end

  it "prefers :expire once age exceeds expire_after even if archive also matches" do
    r = described_class.new(expire_after: "30d", archive_after: "7d")
    expect(r.action_for(2_592_001)).to eq(:expire)
  end

  it "returns nil when no window is set" do
    expect(described_class.new.action_for(10**9)).to be_nil
  end
end
