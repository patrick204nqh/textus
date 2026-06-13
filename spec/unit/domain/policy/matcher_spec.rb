require "spec_helper"

RSpec.describe Textus::Manifest::Policy::Matcher do
  describe "#matches?" do
    it "matches exact dotted keys" do
      expect(described_class.matches?("intake.news.hn", "intake.news.hn")).to be(true)
    end

    it "matches single-segment * wildcard" do
      expect(described_class.matches?("intake.news.*", "intake.news.hn")).to be(true)
      expect(described_class.matches?("intake.news.*", "intake.news.hn.sub")).to be(false)
    end

    it "matches multi-segment ** wildcard" do
      expect(described_class.matches?("intake.**", "intake.news.hn")).to be(true)
      expect(described_class.matches?("intake.**", "intake")).to be(true)
      expect(described_class.matches?("intake.**", "other.news")).to be(false)
    end
  end

  describe "#specificity" do
    it "scores literal segments higher than wildcards" do
      expect(described_class.specificity("intake.news.*")).to be > described_class.specificity("intake.**")
      expect(described_class.specificity("intake.news.hn")).to be > described_class.specificity("intake.news.*")
    end
  end

  describe ".pick_most_specific" do
    it "returns the most-specific glob from a list" do
      globs = ["intake.**", "intake.news.*", "intake.news.hn"]
      expect(described_class.pick_most_specific(globs, key: "intake.news.hn")).to eq("intake.news.hn")
    end

    it "filters out non-matching globs first" do
      globs = ["other.**", "intake.**", "intake.news.*"]
      expect(described_class.pick_most_specific(globs, key: "intake.news.hn")).to eq("intake.news.*")
    end

    it "returns nil if nothing matches" do
      expect(described_class.pick_most_specific(["other.**"], key: "intake.news.hn")).to be_nil
    end
  end
end
