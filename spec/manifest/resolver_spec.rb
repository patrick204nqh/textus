require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe Textus::Manifest::Resolver do
  include_context "textus_store_fixture"

  let(:manifest) { Textus::Manifest.load(root) }
  let(:resolver) { described_class.new(manifest) }

  before do
    FileUtils.mkdir_p(File.join(root, "zones/working"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: working, write_policy: [human] }
      entries:
        - { key: working.notes, path: working/notes.md, zone: working, schema: null, owner: human:self }
    YAML
  end

  it "resolves a leaf key to a Resolution" do
    res = resolver.resolve("working.notes")
    expect(res).to be_a(Textus::Manifest::Resolution)
    expect(res.path).to end_with("/zones/working/notes.md")
  end

  it "raises UnknownKey for missing entries with suggestions" do
    expect { resolver.resolve("working.note") }.to raise_error(Textus::UnknownKey)
  end
end
