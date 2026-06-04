# frozen_string_literal: true

require "spec_helper"

RSpec.describe Textus::Hooks::Signature do
  describe "#accepts_keyrest?" do
    it "returns true for a keyrest callable" do
      sig = described_class.new(->(**kw) {})
      expect(sig.accepts_keyrest?).to be true
    end

    it "returns false for a callable with only declared keyword args" do
      sig = described_class.new(->(a:, b:) {})
      expect(sig.accepts_keyrest?).to be false
    end
  end

  describe "#declared_keys" do
    it "returns the declared keyword parameter names (keyreq + key)" do
      sig = described_class.new(->(a:, b:) {})
      expect(sig.declared_keys).to eq(%i[a b])
    end

    it "includes optional keyword args (:key) alongside required ones" do
      sig = described_class.new(->(a:, b: nil) {})
      expect(sig.declared_keys).to eq(%i[a b])
    end

    it "excludes the keyrest name from declared_keys" do
      sig = described_class.new(->(**kw) {})
      expect(sig.declared_keys).to eq([])
    end
  end

  describe "#missing" do
    it "returns keys not declared when no keyrest" do
      sig = described_class.new(->(a:, b:) {})
      expect(sig.missing(%i[a b c])).to eq(%i[c])
    end

    it "returns empty array when all required keys are declared" do
      sig = described_class.new(->(a:, b:) {})
      expect(sig.missing(%i[a b])).to eq([])
    end

    it "returns empty array when keyrest is present" do
      sig = described_class.new(->(**kw) {})
      expect(sig.missing(%i[a b c])).to eq([])
    end
  end

  describe "#filter" do
    it "filters kwargs to only declared keys when no keyrest" do
      sig = described_class.new(->(a:) {})
      expect(sig.filter(a: 1, z: 9)).to eq({ a: 1 })
    end

    it "returns the full hash when keyrest is present" do
      sig = described_class.new(->(**kw) {})
      expect(sig.filter(a: 1, z: 9)).to eq({ a: 1, z: 9 })
    end
  end
end
