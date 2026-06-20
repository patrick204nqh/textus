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

  it "returns sources in envelope after put with _meta.sources" do
    result = store.as(:human).put("knowledge.notes.test",
                                  meta: { "sources" => ["raw.2026.06.20.url-test"] },
                                  body: "test content\n")
    expect(result.sources).to eq(["raw.2026.06.20.url-test"])
  end

  it "preserves sources across writes" do
    store.as(:human).put("knowledge.notes.test",
                         meta: { "sources" => ["raw.2026.06.20.url-a"] },
                         body: "version 1\n")
    result = store.as(:human).put("knowledge.notes.test",
                                  meta: {}, body: "version 2\n")
    expect(result.sources).to eq(["raw.2026.06.20.url-a"])
  end

  it "replaces sources on explicit write" do
    store.as(:human).put("knowledge.notes.test",
                         meta: { "sources" => ["raw.2026.06.20.url-old"] },
                         body: "old\n")
    result = store.as(:human).put("knowledge.notes.test",
                                  meta: { "sources" => ["raw.2026.06.20.url-new"] },
                                  body: "new\n")
    expect(result.sources).to eq(["raw.2026.06.20.url-new"])
  end

  it "omits sources from envelope when absent" do
    result = store.as(:human).put("knowledge.notes.test",
                                  meta: {}, body: "no sources\n")
    expect(result.sources).to be_nil
  end

  it "rejects put with invalid sources" do
    expect do
      store.as(:human).put("knowledge.notes.test",
                           meta: { "sources" => "bad" }, body: "test\n")
    end.to raise_error(Textus::BadContent)
  end
end
