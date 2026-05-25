require "spec_helper"
require "tmpdir"

RSpec.describe Textus::Role do
  it "accepts canonical actors human/agent/runner/builder" do
    %w[human agent runner builder].each do |a|
      expect(described_class.resolve(root: "/nonexistent", flag: a)).to eq(a)
    end
  end

  it "rejects legacy ai with migration hint" do
    expect do
      described_class.resolve(root: "/nonexistent", flag: "ai")
    end.to raise_error(Textus::InvalidRole, /renamed to 'agent'/)
  end

  it "rejects legacy script with migration hint" do
    expect do
      described_class.resolve(root: "/nonexistent", flag: "script")
    end.to raise_error(Textus::InvalidRole, /renamed to 'runner'/)
  end

  it "rejects legacy build with migration hint" do
    expect do
      described_class.resolve(root: "/nonexistent", flag: "build")
    end.to raise_error(Textus::InvalidRole, /renamed to 'builder'/)
  end

  it "still accepts custom roles that match the regex" do
    expect(described_class.resolve(root: "/nonexistent", flag: "ci")).to eq("ci")
  end
end
