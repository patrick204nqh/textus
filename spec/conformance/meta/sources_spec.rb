# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Sources integration" do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(root, lanes: %w[knowledge], manifest: <<~YAML)
      version: textus/4
      roles:
        - { name: human, can: [author] }
      lanes:
        - { name: knowledge, kind: canon }
      entries:
        - { key: knowledge.notes, lane: knowledge, owner: human:self, nested: true, kind: nested }
    YAML
  end

  it "stores sources as objects with key after put" do
    result = store.with_role(:human).put("knowledge.notes.test",
                                         meta: { "sources" => ["raw.2026.06.20.url-test"] },
                                         body: "test content\n")
    expect(result.sources).to eq([{ "key" => "raw.2026.06.20.url-test" }])
  end

  it "preserves source objects across writes when sources not re-declared" do
    store.with_role(:human).put("knowledge.notes.test",
                                meta: { "sources" => ["raw.2026.06.20.url-a"] },
                                body: "version 1\n")
    result = store.with_role(:human).put("knowledge.notes.test",
                                         meta: {}, body: "version 2\n")
    expect(result.sources).to eq([{ "key" => "raw.2026.06.20.url-a" }])
  end

  it "replaces sources on explicit re-declaration" do
    store.with_role(:human).put("knowledge.notes.test",
                                meta: { "sources" => ["raw.2026.06.20.url-old"] },
                                body: "old\n")
    result = store.with_role(:human).put("knowledge.notes.test",
                                         meta: { "sources" => ["raw.2026.06.20.url-new"] },
                                         body: "new\n")
    expect(result.sources).to eq([{ "key" => "raw.2026.06.20.url-new" }])
  end

  it "omits sources from envelope when absent" do
    result = store.with_role(:human).put("knowledge.notes.test",
                                         meta: {}, body: "no sources\n")
    expect(result.sources).to be_nil
  end

  it "rejects put with non-array sources" do
    expect do
      store.with_role(:human).put("knowledge.notes.test",
                                  meta: { "sources" => "bad" }, body: "test\n")
    end.to raise_error(Textus::BadContent)
  end

  it "snapshots the etag when the referenced entry exists at put time" do
    raw_store = store_from_manifest(root, lanes: %w[raw knowledge], manifest: <<~YAML)
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

    raw_store.with_role(:human).ingest(kind: "file", slug: "test-article",
                                       path: __FILE__, lane: "raw", label: "Test")

    raw_key = raw_store.list(lane: "raw").first["key"]
    raw_etag = raw_store.get(key: raw_key).etag

    result = raw_store.with_role(:human).put("knowledge.notes.article",
                                             meta: { "sources" => [raw_key] },
                                             body: "derived\n")

    expect(result.sources).to eq([{ "key" => raw_key, "etag" => raw_etag }])
  end
end
