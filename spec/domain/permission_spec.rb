require "spec_helper"

RSpec.describe Textus::Domain::Permission do
  describe "#allows_write?" do
    it "returns true when the role is in writers" do
      perm = described_class.new(zone: "working", writers: %w[human automation], read_policy: :all)
      expect(perm.allows_write?("human")).to be(true)
      expect(perm.allows_write?("automation")).to be(true)
    end

    it "returns false when the role is not in writers" do
      perm = described_class.new(zone: "working", writers: ["human"], read_policy: :all)
      expect(perm.allows_write?("automation")).to be(false)
    end

    it "treats symbol roles equivalently to string roles" do
      perm = described_class.new(zone: "working", writers: ["human"], read_policy: :all)
      expect(perm.allows_write?(:human)).to be(true)
    end
  end

  describe "#allows_read?" do
    it "returns true for all roles when read_policy is :all" do
      perm = described_class.new(zone: "working", writers: [], read_policy: :all)
      expect(perm.allows_read?("anything")).to be(true)
    end

    it "returns true when role is listed" do
      perm = described_class.new(zone: "secret", writers: [], read_policy: ["human"])
      expect(perm.allows_read?("human")).to be(true)
      expect(perm.allows_read?("automation")).to be(false)
    end
  end
end
