require "spec_helper"

RSpec.describe Textus::Domain::Permission do
  describe "#allows_write?" do
    it "returns true when the role is in write_policy" do
      perm = described_class.new(zone: "working", write_policy: %w[human runner], read_policy: :all)
      expect(perm.allows_write?("human")).to be(true)
      expect(perm.allows_write?("runner")).to be(true)
    end

    it "returns false when the role is not in write_policy" do
      perm = described_class.new(zone: "working", write_policy: ["human"], read_policy: :all)
      expect(perm.allows_write?("runner")).to be(false)
    end

    it "treats symbol roles equivalently to string roles" do
      perm = described_class.new(zone: "working", write_policy: ["human"], read_policy: :all)
      expect(perm.allows_write?(:human)).to be(true)
    end
  end

  describe "#allows_read?" do
    it "returns true for all roles when read_policy is :all" do
      perm = described_class.new(zone: "working", write_policy: [], read_policy: :all)
      expect(perm.allows_read?("anything")).to be(true)
    end

    it "returns true when role is listed" do
      perm = described_class.new(zone: "secret", write_policy: [], read_policy: ["human"])
      expect(perm.allows_read?("human")).to be(true)
      expect(perm.allows_read?("runner")).to be(false)
    end
  end
end
