require "spec_helper"

RSpec.describe Textus::Domain::Policy::Matcher do
  describe "#matches?" do
    it "matches exact dotted keys" do
      expect(described_class.matches?("inbox.news.hn", "inbox.news.hn")).to be(true)
    end

    it "matches single-segment * wildcard" do
      expect(described_class.matches?("inbox.news.*", "inbox.news.hn")).to be(true)
      expect(described_class.matches?("inbox.news.*", "inbox.news.hn.sub")).to be(false)
    end

    it "matches multi-segment ** wildcard" do
      expect(described_class.matches?("inbox.**", "inbox.news.hn")).to be(true)
      expect(described_class.matches?("inbox.**", "inbox")).to be(true)
      expect(described_class.matches?("inbox.**", "other.news")).to be(false)
    end
  end

  describe "#specificity" do
    it "scores literal segments higher than wildcards" do
      expect(described_class.specificity("inbox.news.*")).to be > described_class.specificity("inbox.**")
      expect(described_class.specificity("inbox.news.hn")).to be > described_class.specificity("inbox.news.*")
    end
  end

  describe ".pick_most_specific" do
    it "returns the most-specific glob from a list" do
      globs = ["inbox.**", "inbox.news.*", "inbox.news.hn"]
      expect(described_class.pick_most_specific(globs, key: "inbox.news.hn")).to eq("inbox.news.hn")
    end

    it "filters out non-matching globs first" do
      globs = ["other.**", "inbox.**", "inbox.news.*"]
      expect(described_class.pick_most_specific(globs, key: "inbox.news.hn")).to eq("inbox.news.*")
    end

    it "returns nil if nothing matches" do
      expect(described_class.pick_most_specific(["other.**"], key: "inbox.news.hn")).to be_nil
    end
  end
end
