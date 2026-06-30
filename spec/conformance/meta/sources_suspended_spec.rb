# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Sources suspended detection" do
  include_context "textus_store_fixture"

  let(:full_store) do
    store_from_manifest(root, lanes: %w[raw knowledge], manifest: <<~YAML)
      version: textus/4
      roles:
        - { name: human, can: [author, ingest] }
      lanes:
        - { name: raw,       kind: raw }
        - { name: knowledge, kind: canon }
      entries:
        - { key: raw,             lane: raw,       owner: human:self, nested: true, kind: nested, format: yaml }
        - { key: knowledge.notes, lane: knowledge, owner: human:self, nested: true, kind: nested }
    YAML
  end

  def ingest_file(store)
    store.with_role(:human).entry(:ingest, kind: "file", slug: "article", path: __FILE__,
                                           lane: "raw", label: "Article")
    store.entry(:list, lane: "raw").first["key"]
  end

  it "marks sources as not suspended when etag matches" do
    raw_key = ingest_file(full_store)
    raw_etag = full_store.entry(:get, key: raw_key).etag

    full_store.with_role(:human).entry(:put, key: "knowledge.notes.derived",
                                             meta: { "sources" => [raw_key] },
                                             body: "derived\n")

    result = full_store.entry(:get, key: "knowledge.notes.derived")
    src = result.sources.first

    expect(src["key"]).to eq(raw_key)
    expect(src["etag"]).to eq(raw_etag)
    expect(src["suspended"]).to be false
  end

  it "marks sources as suspended when source etag changed after put" do
    raw_key = ingest_file(full_store)

    full_store.with_role(:human).entry(:put, key: "knowledge.notes.derived",
                                             meta: { "sources" => [raw_key] },
                                             body: "derived\n")

    raw_path = full_store.entry(:get, key: raw_key).path
    File.write(raw_path, File.read(raw_path) + "\n# changed\n")

    result = full_store.entry(:get, key: "knowledge.notes.derived")
    src = result.sources.first

    expect(src["key"]).to eq(raw_key)
    expect(src["suspended"]).to be true
  end

  it "does not set suspended when source has no stored etag" do
    path = File.join(root, "data/knowledge/notes/legacy.md")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "---\nuid: legacy-uid\nsources:\n- key: raw.some.entry\n---\nlegacy\n")

    result = full_store.entry(:get, key: "knowledge.notes.legacy")
    src = result.sources.first

    expect(src["key"]).to eq("raw.some.entry")
    expect(src["suspended"]).to be false
  end
end
