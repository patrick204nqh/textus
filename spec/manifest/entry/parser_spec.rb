require "spec_helper"

RSpec.describe Textus::Manifest::Entry::Parser do
  let(:manifest) do
    instance_double(Textus::Manifest).tap do |m|
      allow(m).to receive(:zone_writers).with("working").and_return(["human"])
      allow(m).to receive(:zone_writers).with("output").and_return(["builder"])
      allow(m).to receive(:zone_writers).with("intake").and_return(["builder"])
      allow(m).to receive(:zone_writers).with("z").and_return(["human"])
      allow(m).to receive(:zone_writers).with("o").and_return(["builder"])
      allow(m).to receive(:zone_writers).with("i").and_return(["builder"])
    end
  end

  describe ".call" do
    it "extracts the required fields" do
      entry = described_class.call(
        manifest,
        { "key" => "working.foo", "path" => "foo.md", "zone" => "working" },
      )
      expect(entry.key).to eq("working.foo")
      expect(entry.path).to eq("foo.md")
      expect(entry.zone).to eq("working")
      expect(entry.nested).to be false
      expect(entry.events).to eq({})
      expect(entry.publish_to).to eq([])
      expect(entry.publish_each).to be_nil
      expect(entry.inject_intro).to be false
      expect(entry.format).to eq("markdown")
    end

    it "raises when key is missing" do
      expect { described_class.call(manifest, { "path" => "foo.md", "zone" => "working" }) }
        .to raise_error(Textus::UsageError, /manifest entry missing key/)
    end

    it "raises when path is missing" do
      expect { described_class.call(manifest, { "key" => "working.foo", "zone" => "working" }) }
        .to raise_error(Textus::UsageError, /missing path/)
    end

    it "raises when zone is missing" do
      expect { described_class.call(manifest, { "key" => "working.foo", "path" => "foo.md" }) }
        .to raise_error(Textus::UsageError, /missing zone/)
    end

    it "extracts compute: projection" do
      entry = described_class.call(
        manifest,
        {
          "key" => "output.foo", "path" => "foo.md", "zone" => "output",
          "compute" => { "kind" => "projection", "select" => ["working.bar"] },
          "template" => "x.mustache"
        },
      )
      expect(entry.projection).to eq({ "kind" => "projection", "select" => ["working.bar"] })
      expect(entry.generator).to be_nil
    end

    it "extracts compute: external" do
      entry = described_class.call(
        manifest,
        {
          "key" => "output.foo", "path" => "foo.md", "zone" => "output",
          "compute" => { "kind" => "external", "command" => "echo hi" }
        },
      )
      expect(entry.generator).to eq({ "kind" => "external", "command" => "echo hi" })
      expect(entry.projection).to be_nil
    end

    it "rejects unknown compute.kind" do
      expect do
        described_class.call(
          manifest,
          {
            "key" => "output.foo", "path" => "foo.md", "zone" => "output",
            "compute" => { "kind" => "weird" }
          },
        )
      end.to raise_error(Textus::BadManifest, /compute.kind must be one of/)
    end

    it "extracts intake config" do
      entry = described_class.call(
        manifest,
        {
          "key" => "intake.foo", "path" => "foo.md", "zone" => "intake",
          "intake" => { "handler" => "pull_foo", "config" => { "url" => "x" } },
          "template" => "x.mustache"
        },
      )
      expect(entry.intake_handler).to eq("pull_foo")
      expect(entry.intake_config).to eq({ "url" => "x" })
    end

    it "parses an explicit leaf row" do
      e = described_class.call(manifest, { "key" => "z.a", "path" => "z/a.md", "zone" => "z", "kind" => "leaf" })
      expect(e).to be_a(Textus::Manifest::Entry::Leaf)
    end

    it "parses an explicit nested row" do
      e = described_class.call(manifest, { "key" => "z.n", "path" => "z/n", "zone" => "z", "kind" => "nested" })
      expect(e).to be_a(Textus::Manifest::Entry::Nested)
    end

    it "parses an explicit derived/projection row" do
      e = described_class.call(manifest, { "key" => "o.x", "path" => "o/x.md", "zone" => "o", "kind" => "derived",
                                           "compute" => { "kind" => "projection", "select" => "z.n" } })
      expect(e).to be_a(Textus::Manifest::Entry::Derived)
      expect(e).to be_projection
    end

    it "parses an explicit intake row" do
      e = described_class.call(manifest, { "key" => "i.x", "path" => "i/x.md", "zone" => "i", "kind" => "intake",
                                           "intake" => { "handler" => "h" } })
      expect(e).to be_a(Textus::Manifest::Entry::Intake)
      expect(e.handler).to eq("h")
    end

    it "raises on unknown kind" do
      expect do
        described_class.call(manifest, { "key" => "z.a", "path" => "z/a.md", "zone" => "z", "kind" => "bogus" })
      end.to raise_error(Textus::BadManifest, /unknown kind/)
    end
  end

  describe "kind inference (backward compat)" do
    it "infers nested from nested: true" do
      e = described_class.call(manifest, { "key" => "z.n", "path" => "z/n", "zone" => "z", "nested" => true })
      expect(e).to be_a(Textus::Manifest::Entry::Nested)
    end

    it "infers derived from template:" do
      e = described_class.call(manifest, { "key" => "o.x", "path" => "o/x.md", "zone" => "o", "template" => "t.mustache" })
      expect(e).to be_a(Textus::Manifest::Entry::Derived)
    end

    it "infers intake from intake:" do
      e = described_class.call(manifest, { "key" => "i.x", "path" => "i/x.md", "zone" => "i",
                                           "intake" => { "handler" => "h" } })
      expect(e).to be_a(Textus::Manifest::Entry::Intake)
    end

    it "defaults to leaf" do
      e = described_class.call(manifest, { "key" => "z.a", "path" => "z/a.md", "zone" => "z" })
      expect(e).to be_a(Textus::Manifest::Entry::Leaf)
    end
  end
end
