require "spec_helper"

RSpec.describe Textus::Domain::Policy::Source do
  describe "from: handler (intake)" do
    subject(:src) do
      described_class.new("from" => "handler", "handler" => "calendar_feed",
                          "config" => { "url" => "u" }, "ttl" => "1h")
    end

    it "is the intake kind" do
      expect(src.kind).to eq(:intake)
    end

    it "exposes handler + config + ttl" do
      expect(src.handler).to eq("calendar_feed")
      expect(src.config).to eq("url" => "u")
      expect(src.ttl_seconds).to eq(3600)
    end

    it "is never sync (on_write is meaningless for intake)" do
      expect(src.sync?).to be(false)
    end
  end

  describe "from: template (derived projection)" do
    subject(:src) do
      described_class.new("from" => "template", "template" => "c.mustache",
                          "project" => { "select" => "k.*", "pluck" => ["title"] },
                          "on_write" => "sync", "inject_boot" => true)
    end

    it "is the derived kind" do
      expect(src.kind).to eq(:derived)
    end

    it "exposes the projection + flags" do
      expect(src.template).to eq("c.mustache")
      expect(src.project).to eq("select" => "k.*", "pluck" => ["title"])
      expect(src.inject_boot).to be(true)
      expect(src.sync?).to be(true)
    end

    it "defaults on_write to async, provenance to true" do
      s = described_class.new("from" => "template", "template" => "c.mustache")
      expect(s.sync?).to be(false)
      expect(s.provenance).to be(true)
    end

    it "exposes projection field accessors" do
      expect(src.select).to eq("k.*")
      expect(src.pluck).to eq(["title"])
      expect(src.sort_by).to be_nil
      expect(src.transform).to be_nil
    end

    it "exposes projection_spec as the project hash" do
      expect(src.projection_spec).to eq("select" => "k.*", "pluck" => ["title"])
    end
  end

  describe "from: command (derived external)" do
    subject(:src) do
      described_class.new("from" => "command", "command" => "make build",
                          "sources" => ["src/*"])
    end

    it "is the derived kind and external" do
      expect(src.kind).to eq(:derived)
      expect(src.external?).to be(true)
    end

    it "returns nil ttl_seconds when no ttl is set" do
      expect(src.ttl_seconds).to be_nil
    end

    it "has nil projection accessors and empty projection_spec when not a template" do
      expect(src.select).to be_nil
      expect(src.projection_spec).to eq({})
    end
  end

  describe "validation" do
    it "rejects an unknown from" do
      expect { described_class.new("from" => "psychic") }
        .to raise_error(Textus::BadManifest, /from must be one of/)
    end

    it "rejects a missing handler for from: handler" do
      expect { described_class.new("from" => "handler") }
        .to raise_error(Textus::BadManifest, /handler/)
    end

    it "rejects an unknown on_write strategy" do
      expect { described_class.new("from" => "template", "template" => "c", "on_write" => "later") }
        .to raise_error(Textus::BadManifest, /on_write must be one of/)
    end

    it "rejects a missing template for from: template" do
      expect { described_class.new("from" => "template") }
        .to raise_error(Textus::BadManifest, /template/)
    end

    it "rejects a missing command for from: command" do
      expect { described_class.new("from" => "command") }
        .to raise_error(Textus::BadManifest, /command/)
    end
  end
end
