# frozen_string_literal: true

require "spec_helper"

RSpec.describe Textus::Index::Lookup do
  subject(:lookup) { described_class.new(store: store) }

  let(:root) { File.join(Dir.mktmpdir, ".textus") }
  let(:store) { Textus::Port::Store.new(root: root).setup! }

  after do
    store.close
    FileUtils.rm_rf(File.dirname(root))
  end

  before do
    store.connection.execute(
      "INSERT INTO entries (key, lane, format, etag, content, extra, indexed_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
      ["raw.2026.06.19.url-example", "raw", "yaml", "etag", "needle phrase",
       JSON.dump("content_hash" => "sha256:abc", "url" => "https://example.com"), Time.now.utc.iso8601],
    )
    store.connection.execute(
      "INSERT INTO entries (key, lane, format, etag, content, extra, indexed_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
      ["knowledge.note", "knowledge", "markdown", "etag2", "needle other", JSON.dump({}), Time.now.utc.iso8601],
    )
    store.connection.execute("INSERT INTO entries_fts(entries_fts) VALUES('rebuild')")
  end

  it "finds by content hash" do
    expect(lookup.find_by_hash("sha256:abc")).to eq("raw.2026.06.19.url-example")
  end

  it "finds by url" do
    expect(lookup.find_by_url("https://example.com")).to eq("raw.2026.06.19.url-example")
  end

  it "returns nil for nil url" do
    expect(lookup.find_by_url(nil)).to be_nil
  end

  it "returns ranked search results with lane filtering" do
    expect(lookup.search("needle", lane: "knowledge").map { |row| row["key"] }).to eq(["knowledge.note"])
  end

  it "returns empty results when entries are missing" do
    store.connection.execute("DELETE FROM entries")
    expect(lookup.search("needle")).to eq([])
    expect(lookup.find_by_hash("sha256:abc")).to be_nil
    expect(lookup.find_by_url("https://example.com")).to be_nil
  end
end
