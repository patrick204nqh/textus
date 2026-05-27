require "spec_helper"
require "fileutils"

RSpec.describe Textus::Manifest::Resolution do
  include_context "textus_store_fixture"

  before do
    FileUtils.mkdir_p(File.join(root, "zones"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones: [{ name: working, write_policy: [human] }]
      entries:
        - { key: working.x,   path: working/x.md,   zone: working }
        - { key: working.dir, path: working/dir,    zone: working, nested: true }
    YAML
  end

  let(:manifest) { Textus::Manifest.load(root) }

  it "returns a Resolution for a leaf key with empty remaining" do
    res = manifest.resolver.resolve("working.x")

    expect(res).to be_a(described_class)
    expect(res.entry).to be_a(Textus::Manifest::Entry)
    expect(res.entry.key).to eq("working.x")
    expect(res.path).to eq(File.join(root, "zones/working/x.md"))
    expect(res.remaining).to eq([])
  end

  it "returns a Resolution for a nested key with remaining segments" do
    res = manifest.resolver.resolve("working.dir.alpha.beta")

    expect(res).to be_a(described_class)
    expect(res.entry.key).to eq("working.dir")
    expect(res.path).to end_with("zones/working/dir/alpha/beta.md")
    expect(res.remaining).to eq(%w[alpha beta])
  end

  it "supports Data value equality" do
    a = manifest.resolver.resolve("working.x")
    b = manifest.resolver.resolve("working.x")

    expect(a).to eq(b)
    expect(a.hash).to eq(b.hash)
  end

  it "raises UnknownKey for keys outside the manifest" do
    expect { manifest.resolver.resolve("nope.nada") }.to raise_error(Textus::UnknownKey)
  end
end
