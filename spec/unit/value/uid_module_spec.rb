require "spec_helper"

RSpec.describe Textus::Value::Uid do
  describe ".mint" do
    it "returns a 16-char lowercase hex string" do
      uid = described_class.mint
      expect(uid).to be_a(String)
      expect(uid.length).to eq(16)
      expect(uid).to match(/\A[0-9a-f]{16}\z/)
    end

    it "returns distinct values across calls (sanity)" do
      uids = Array.new(10) { described_class.mint }
      expect(uids.uniq.size).to eq(uids.size)
    end
  end

  describe ".valid?" do
    it "returns true for a 16-char lowercase hex string" do
      expect(described_class.valid?("0123456789abcdef")).to be(true)
    end

    it "returns false for nil" do
      expect(described_class.valid?(nil)).to be(false)
    end

    it "returns false for an empty string" do
      expect(described_class.valid?("")).to be(false)
    end

    it "returns false for an uppercase hex string" do
      expect(described_class.valid?("0123456789ABCDEF")).to be(false)
    end

    it "returns false for a 15-char string" do
      expect(described_class.valid?("0123456789abcde")).to be(false)
    end

    it "returns false for a 17-char string" do
      expect(described_class.valid?("0123456789abcdef0")).to be(false)
    end

    it "returns false for a non-hex string" do
      expect(described_class.valid?("zzzzzzzzzzzzzzzz")).to be(false)
    end
  end
end
