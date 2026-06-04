require "spec_helper"

RSpec.describe Textus::Manifest::Entry::Derived, ".from_raw provenance" do
  def common
    {
      raw: {}, key: "output.config", path: "output/config.json", zone: "output",
      schema: nil, owner: nil, format: "json", publish_to: []
    }
  end

  def projection_source
    Textus::Manifest::Entry::Derived::Projection.new(
      select: ["working.*"], pluck: nil, sort_by: nil, transform: nil,
    )
  end

  describe "default (no provenance key in raw)" do
    it "defaults provenance to true" do
      raw = {
        "compute" => { "kind" => "projection", "select" => ["working.*"] },
      }
      entry = described_class.from_raw(common, raw)
      expect(entry.provenance).to be(true)
    end
  end

  describe "explicit provenance: false" do
    it "parses provenance as false" do
      raw = {
        "compute" => { "kind" => "projection", "select" => ["working.*"] },
        "provenance" => false,
      }
      entry = described_class.from_raw(common, raw)
      expect(entry.provenance).to be(false)
    end
  end

  describe "explicit provenance: true" do
    it "parses provenance as true" do
      raw = {
        "compute" => { "kind" => "projection", "select" => ["working.*"] },
        "provenance" => true,
      }
      entry = described_class.from_raw(common, raw)
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
