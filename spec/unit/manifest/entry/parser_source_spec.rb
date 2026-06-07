require "spec_helper"

RSpec.describe Textus::Manifest::Entry::Parser do
  describe ".parse_source" do
    it "builds a Source policy from a project block" do
      raw = { "source" => { "from" => "project", "select" => ["working.a"] } }
      src = described_class.parse_source(raw, "out.catalog")
      expect(src).to be_a(Textus::Domain::Policy::Source)
      expect(src.kind).to eq(:derived)
    end

    it "builds a Source policy from a handler block" do
      raw = { "source" => { "from" => "handler", "handler" => "h" } }
      src = described_class.parse_source(raw, "feeds.doc")
      expect(src.kind).to eq(:intake)
    end

    it "builds a Source policy from a command block" do
      raw = { "source" => { "from" => "command", "command" => "make" } }
      src = described_class.parse_source(raw, "feeds.ext")
      expect(src.external?).to be(true)
    end

    it "raises when source: is absent" do
      expect { described_class.parse_source({}, "x.y") }
        .to raise_error(Textus::BadManifest, /requires a source:/)
    end
  end
end
