require "spec_helper"

RSpec.describe Textus::Manifest::Entry::IgnoreMatcher do
  describe ".match?" do
    it "returns false when patterns are empty" do
      expect(described_class.match?([], "node_modules/foo/SKILL.md")).to be(false)
    end

    it "matches a vendored subtree at the root via **/dir/**" do
      expect(described_class.match?(["**/node_modules/**"], "node_modules/foo/SKILL.md")).to be(true)
    end

    it "matches a vendored subtree nested below other dirs" do
      expect(described_class.match?(["**/node_modules/**"], "pkg/a/node_modules/dep/SKILL.md")).to be(true)
    end

    it "does not match a sibling path that merely shares a prefix" do
      expect(described_class.match?(["**/node_modules/**"], "node_modules_notes/SKILL.md")).to be(false)
    end

    it "respects FNM_PATHNAME — a single * does not cross a slash" do
      expect(described_class.match?(["*.md"], "a/b.md")).to be(false)
      expect(described_class.match?(["*.md"], "b.md")).to be(true)
    end

    it "supports brace alternation via FNM_EXTGLOB" do
      expect(described_class.match?(["**/{dist,build}/**"], "x/dist/out/SKILL.md")).to be(true)
      expect(described_class.match?(["**/{dist,build}/**"], "x/build/out/SKILL.md")).to be(true)
    end

    it "returns true if any pattern in the list matches" do
      expect(described_class.match?(["**/dist/**", "**/node_modules/**"], "node_modules/x/SKILL.md")).to be(true)
    end
  end
end
