require "spec_helper"

RSpec.describe Textus::Read::Freshness do
  subject(:rows) { described_class.new(container: store.container, call: test_ctx(role: "automation")).call }

  include_context "textus_store_fixture"

  let!(:store) do
    store_from_manifest(root, zones: %w[feeds review],
                              files: {
                                "data/feeds/doc.md" => "---\n---\nx\n",
                                "data/review/old.md" => "---\n---\nx\n",
                              },
                              manifest: <<~YAML)
                                version: textus/3
                                zones:
                                  - { name: feeds, kind: machine }
                                  - { name: review, kind: canon }
                                entries:
                                  - { key: feeds.doc, kind: produced, path: feeds/doc.md, zone: feeds, source: { from: handler, handler: h, ttl: 1h } }
                                  - { key: review.old, path: review/old.md, zone: review, kind: leaf }
                                rules:
                                  - { match: "review.*", retention: { ttl: 1d, action: archive } }
                              YAML
  end

  it "marks an intake entry past source.ttl as expired" do
    File.utime(Time.now - 7200, Time.now - 7200, File.join(root, "data/feeds/doc.md"))
    row = rows.find { |r| r[:key] == "feeds.doc" }
    expect(row[:status]).to eq(:expired)
    expect(row[:action]).to eq(:refresh)
  end

  it "marks an entry past its retention ttl as expired with the GC action" do
    File.utime(Time.now - (2 * 86_400), Time.now - (2 * 86_400), File.join(root, "data/review/old.md"))
    row = rows.find { |r| r[:key] == "review.old" }
    expect(row[:status]).to eq(:expired)
    expect(row[:action]).to eq(:archive)
  end

  it "marks a fresh intake entry as fresh" do
    row = rows.find { |r| r[:key] == "feeds.doc" }
    expect(row[:status]).to eq(:fresh)
  end

  it "marks a fresh retention-governed entry as fresh" do
    row = rows.find { |r| r[:key] == "review.old" }
    expect(row[:status]).to eq(:fresh)
  end
end
