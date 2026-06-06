require "spec_helper"

RSpec.describe Textus::Domain::IntakeStaleness do
  subject(:keys) do
    described_class.new(
      manifest: store.manifest,
      file_stat: Textus::Ports::Storage::FileStat.new,
      clock: Textus::Ports::Clock,
    ).call
  end

  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(root, zones: %w[feeds], manifest: <<~YAML,
      version: textus/3
      zones: [{ name: feeds, kind: machine }]
      entries:
        - { key: feeds.doc, kind: intake, path: feeds/doc.md, zone: feeds, source: { from: handler, handler: h, ttl: 1h } }
    YAML
                              files: { "zones/feeds/doc.md" => "---\n---\nbody\n" })
  end

  before { store }

  it "lists an intake entry past its source.ttl" do
    path = File.join(root, "zones/feeds/doc.md")
    old  = Time.now - (2 * 3600)
    File.utime(old, old, path)
    expect(keys).to eq(["feeds.doc"])
  end

  it "omits a fresh intake entry" do
    expect(keys).to be_empty
  end
end
