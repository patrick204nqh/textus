require "spec_helper"

RSpec.describe "init scaffolds machine surfaces" do
  describe "feeds.machines snapshot" do
    around { |ex| Dir.mktmpdir { |d| Dir.chdir(d) { ex.run } } }

    before { Textus::Init.run(File.join(Dir.pwd, ".textus")) }

    it "does not scaffold steps/ directories" do
      expect(File).not_to exist(".textus/steps")
    end

    it "no longer creates cursors, locks, or queue runtime dirs" do
      expect(File.directory?(File.join(Dir.pwd, ".textus/.state/cursors"))).to be(false)
      expect(File.directory?(File.join(Dir.pwd, ".textus/.state/locks"))).to be(false)
      expect(File.directory?(File.join(Dir.pwd, ".textus/.state/queue"))).to be(false)
      expect(File.exist?(File.join(Dir.pwd, ".textus/.state/store.db"))).to be(false)
    end

    it "declares a nested artifacts.feeds.machines entry, tracked:false, in the artifacts zone" do
      manifest = Textus::Manifest.load(File.join(Dir.pwd, ".textus"))
      entry = manifest.data.entries.find { |e| e.key == "artifacts.feeds.machines" }
      expect(entry).not_to be_nil
      expect(entry.nested?).to be(true)
      expect(entry.tracked?).to be(false)
      expect(entry.publish_to).to eq([]) # never published (sensitive)
      expect(entry.lane).to eq("artifacts")
    end

    it "gitignores the whole nested subtree (and still the state subtree)" do
      ignore = File.read(".textus/.gitignore")
      expect(ignore).to include("#{Textus::Store::Layout::RUN}/")
      expect(ignore).to include("data/artifacts/feeds/machines/")
    end
  end

  describe "Setup-1 zone kinds (ADR 0033)" do
    it "declares the four Setup-1 zones with the right kinds and validates" do
      raw = YAML.safe_load(Textus::Init::DEFAULT_MANIFEST, aliases: false)
      kinds = raw["lanes"].to_h { |z| [z["name"], z["kind"]] }
      expect(kinds).to eq(
        "knowledge" => "canon", "scratchpad" => "workspace",
        "proposals" => "queue", "artifacts" => "machine"
      )
      expect { Textus::Manifest::Schema.validate!(raw) }.not_to raise_error
    end

    it "gives agent a keep capability and human author" do
      raw = YAML.safe_load(Textus::Init::DEFAULT_MANIFEST, aliases: false)
      caps = raw["roles"].to_h { |r| [r["name"], r["can"]] }
      expect(caps["agent"]).to include("keep")
      expect(caps["human"]).to include("author")
    end
  end
end
