require "spec_helper"

RSpec.describe Textus::Manifest::Entry::Derived, ".from_raw provenance" do
  def common
    {
      raw: {}, key: "output.config", path: "output/config.json", zone: "output",
      schema: nil, owner: nil, format: "json", publish_to: []
    }
  end

  def source_raw(extra = {})
    {
      "source" => {
        "from" => "template", "template" => "t.mustache",
        "project" => { "select" => ["working.*"] }
      }.merge(extra),
    }
  end

  describe "default (no provenance key in raw)" do
    it "defaults provenance to true" do
      entry = described_class.from_raw(common, source_raw)
      expect(entry.provenance).to be(true)
    end
  end

  describe "explicit source.provenance: false" do
    it "parses provenance as false" do
      entry = described_class.from_raw(common, source_raw("provenance" => false))
      expect(entry.provenance).to be(false)
    end
  end

  describe "explicit source.provenance: true" do
    it "parses provenance as true" do
      entry = described_class.from_raw(common, source_raw("provenance" => true))
      expect(entry.provenance).to be(true)
    end
  end

  describe "base default" do
    it "Base entry also responds to provenance with true" do
      base = Textus::Manifest::Entry::Base.new(
        raw: {}, key: "z.a", path: "z/a.md", zone: "z",
        schema: nil, owner: nil, format: "markdown"
      )
      expect(base.provenance).to be(true)
    end
  end
end
