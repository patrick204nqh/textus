require "spec_helper"

RSpec.describe Textus::Manifest::Policy::Source do
  describe "from: derive (internal data)" do
    subject(:src) do
      described_class.new("from" => "derive", "select" => ["k.*"],
                          "pluck" => ["title"], "transform" => "reducer")
    end

    it "is derived, observable, not external" do
      expect(src.kind).to eq(:derived)
      expect(src.projection?).to be(true)
      expect(src.external?).to be(false)
    end

    it "exposes flattened projection fields + projection_spec" do
      expect(src.select).to eq(["k.*"])
      expect(src.transform).to eq("reducer")
      expect(src.projection_spec).to eq("select" => ["k.*"], "pluck" => ["title"], "transform" => "reducer")
    end
  end

  describe "from: fetch (intake)" do
    subject(:src) { described_class.new("from" => "fetch", "handler" => "h", "config" => { "u" => 1 }, "ttl" => "1h") }

    it "is intake, exposes handler/config/ttl" do
      expect(src.kind).to eq(:intake)
      expect(src.handler).to eq("h")
      expect(src.config).to eq("u" => 1)
      expect(src.ttl_seconds).to eq(3600)
    end
  end

  describe "from: external (external)" do
    subject(:src) { described_class.new("from" => "external", "command" => "make", "sources" => ["s/*"]) }

    it "is external" do
      expect(src.kind).to eq(:external)
      expect(src.external?).to be(true)
      expect(src.command).to eq("make")
      expect(src.sources).to eq(["s/*"])
    end
  end

  describe "retired vocabulary" do
    it "rejects from: handler (renamed to fetch)" do
      expect { described_class.new("from" => "handler", "handler" => "h") }
        .to raise_error(Textus::BadManifest, /fetch/)
    end

    it "no longer exposes template/inject_boot/provenance" do
      src = described_class.new("from" => "derive", "select" => ["k"])
      %i[template inject_boot provenance].each { |m| expect(src).not_to respond_to(m) }
    end
  end
end
