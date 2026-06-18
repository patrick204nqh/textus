# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Textus::Ports::RawIndex do
  subject(:raw_index) { described_class.new(root: root) }

  let(:tmp) { Dir.mktmpdir }
  let(:root) { File.join(tmp, ".textus") }

  before { FileUtils.mkdir_p(File.dirname(Textus::Layout.raw_index(root))) }
  after { FileUtils.remove_entry(tmp) }

  it "loads an empty index when no file exists" do
    index = raw_index.load
    expect(index).to eq({ "hashes" => {}, "urls" => {} })
  end

  it "round-trips a saved index" do
    index = { "hashes" => { "sha256:abc" => "raw.2026.06.18.url-foo" }, "urls" => {} }
    raw_index.save(index)
    expect(raw_index.load).to eq(index)
  end

  it "returns nil for unknown hash" do
    expect(raw_index.find_by_hash("sha256:nonexistent")).to be_nil
  end

  it "returns nil for unknown url" do
    expect(raw_index.find_by_url("https://unknown.example.com")).to be_nil
  end

  it "returns nil for nil url" do
    expect(raw_index.find_by_url(nil)).to be_nil
  end

  it "finds an entry by content hash after upsert" do
    raw_index.upsert(content_hash: "sha256:abc", url: "https://example.com", key: "raw.2026.06.18.url-foo")
    expect(raw_index.find_by_hash("sha256:abc")).to eq("raw.2026.06.18.url-foo")
  end

  it "finds an entry by url after upsert" do
    raw_index.upsert(content_hash: "sha256:abc", url: "https://example.com", key: "raw.2026.06.18.url-foo")
    expect(raw_index.find_by_url("https://example.com")).to eq("raw.2026.06.18.url-foo")
  end

  it "updates an existing hash entry on re-ingest" do
    raw_index.upsert(content_hash: "sha256:abc", url: "https://example.com", key: "raw.2026.06.10.url-foo")
    raw_index.upsert(content_hash: "sha256:abc", url: "https://example.com", key: "raw.2026.06.18.url-foo")
    expect(raw_index.find_by_hash("sha256:abc")).to eq("raw.2026.06.18.url-foo")
  end

  it "handles url nil in upsert (file/asset kinds)" do
    raw_index.upsert(content_hash: "sha256:def", url: nil, key: "raw.2026.06.18.file-foo")
    expect(raw_index.find_by_hash("sha256:def")).to eq("raw.2026.06.18.file-foo")
    index = raw_index.load
    expect(index["urls"]).to eq({})
  end

  it "returns path via Layout.raw_index" do
    expect(raw_index.path).to eq(Textus::Layout.raw_index(root))
  end

  it "recovers from corrupt index file" do
    File.write(raw_index.path, "not: valid: yaml: [")
    expect(raw_index.load).to eq({ "hashes" => {}, "urls" => {} })
  end
end
