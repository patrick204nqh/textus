require "spec_helper"

RSpec.describe Textus::Domain::Permission do
  describe "#allows_write?" do
    it "returns true when the role is in writers" do
      perm = described_class.new(zone: "working", writers: %w[human automation])
      expect(perm.allows_write?("human")).to be(true)
      expect(perm.allows_write?("automation")).to be(true)
    end

    it "returns false when the role is not in writers" do
      perm = described_class.new(zone: "working", writers: ["human"])
      expect(perm.allows_write?("automation")).to be(false)
    end

    it "treats symbol roles equivalently to string roles" do
      perm = described_class.new(zone: "working", writers: ["human"])
      expect(perm.allows_write?(:human)).to be(true)
    end
  end
end
