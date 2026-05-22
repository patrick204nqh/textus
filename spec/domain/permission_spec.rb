require "spec_helper"

RSpec.describe Textus::Domain::Permission do
  describe "#allows_write?" do
    it "returns true when the role is in writable_by" do
      perm = described_class.new(zone: "working", writable_by: %w[human script], readable_by: :all)
      expect(perm.allows_write?("human")).to be(true)
      expect(perm.allows_write?("script")).to be(true)
    end

    it "returns false when the role is not in writable_by" do
      perm = described_class.new(zone: "working", writable_by: ["human"], readable_by: :all)
      expect(perm.allows_write?("script")).to be(false)
    end

    it "treats symbol roles equivalently to string roles" do
      perm = described_class.new(zone: "working", writable_by: ["human"], readable_by: :all)
      expect(perm.allows_write?(:human)).to be(true)
    end
  end

  describe "#allows_read?" do
    it "returns true for all roles when readable_by is :all" do
      perm = described_class.new(zone: "working", writable_by: [], readable_by: :all)
      expect(perm.allows_read?("anything")).to be(true)
    end

    it "returns true when role is listed" do
      perm = described_class.new(zone: "secret", writable_by: [], readable_by: ["human"])
      expect(perm.allows_read?("human")).to be(true)
      expect(perm.allows_read?("script")).to be(false)
    end
  end
end
