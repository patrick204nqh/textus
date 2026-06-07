require "spec_helper"

RSpec.describe Textus::Domain::Retention do
  subject(:rows) do
    described_class.new(
      manifest: store.manifest,
      file_stat: Textus::Ports::Storage::FileStat.new,
      clock: Textus::Ports::Clock,
    ).call
  end

  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(root, zones: %w[review], manifest: <<~YAML,
      version: textus/3
      zones: [{ name: review, kind: canon }]
      entries: [{ key: review.old, path: review/old.md, zone: review, kind: leaf }]
      rules: [{ match: "review.*", retention: { ttl: 1d, action: archive } }]
    YAML
                              files: { "zones/review/old.md" => "---\n---\nbody\n" })
  end

  before { store }

  it "returns an archive row for an aged leaf" do
    path = File.join(root, "zones/review/old.md")
    old  = Time.now - (2 * 24 * 3600)
    File.utime(old, old, path)
    expect(rows).to contain_exactly(include("key" => "review.old", "action" => "archive"))
  end

  it "returns nothing for a fresh leaf" do
    expect(rows).to be_empty
  end
end
