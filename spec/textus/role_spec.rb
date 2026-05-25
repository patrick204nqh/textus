require "spec_helper"
require "tmpdir"

RSpec.describe Textus::Role do
  it "accepts canonical actors human/agent/runner/builder" do
    %w[human agent runner builder].each do |a|
      expect(described_class.resolve(root: "/nonexistent", flag: a)).to eq(a)
    end
  end

  it "still accepts custom roles that match the regex" do
    expect(described_class.resolve(root: "/nonexistent", flag: "ci")).to eq("ci")
  end
end
