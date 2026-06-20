# frozen_string_literal: true

require "spec_helper"

RSpec.describe Textus::Index::Builder do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(root, lanes: %w[knowledge raw artifacts], manifest: <<~YAML, files: files)
      version: textus/4
      roles:
        - { name: human,      can: [author, ingest] }
        - { name: agent,      can: [propose, keep, ingest] }
        - { name: automation, can: [converge] }
      lanes:
        - { name: knowledge, kind: canon }
        - { name: raw, kind: raw }
        - { name: artifacts, kind: machine }
      entries:
        - { key: knowledge.a, path: knowledge/a.md, lane: knowledge, kind: leaf }
        - { key: raw, path: raw, lane: raw, nested: true, kind: nested, format: yaml }
        - { key: artifacts.system.index, path: artifacts/system/index.json, lane: artifacts, kind: leaf, format: json }
    YAML
  end

  let(:files) do
    {
      "data/knowledge/a.md" => "---\ntitle: Alpha\n---\nBody alpha term\n",
      "data/raw/2026/06/19/url-example.yaml" => <<~YAML,
        ---
        ingested_at: "2026-06-19T00:00:00Z"
        content_hash: sha256:abc
        source:
          kind: url
          url: https://example.com
          label: Example
        body:
      YAML
    }
  end

  let(:store_port) { Textus::Port::Store.new(root: root).setup! }

  after { store_port.close }

  it "rebuilds entries and FTS rows from resolver enumeration" do
    result = described_class.new(store: store_port).rebuild!(resolver: store.container.manifest.resolver)

    expect(result).to eq({ indexed: 2 })
    rows = store_port.connection.execute("SELECT key, lane, format, extra FROM entries ORDER BY key")
    expect(rows.map { |row| row["key"] }).to eq(["knowledge.a", "raw.2026.06.19.url-example"])
    expect(rows.first["lane"]).to eq("knowledge")
    raw_extra = JSON.parse(rows.last["extra"])
    expect(raw_extra).to include("content_hash" => "sha256:abc", "url" => "https://example.com")

    matches = store_port.connection.execute("SELECT key FROM entries_fts WHERE entries_fts MATCH 'alpha'")
    expect(matches.map { |row| row["key"] }).to eq(["knowledge.a"])
  end

  it "keeps the old index when rebuild fails mid-transaction" do
    described_class.new(store: store_port).rebuild!(resolver: store.container.manifest.resolver)
    existing = store.container.manifest.resolver.enumerate.first[:path]
    bad_resolver = instance_double(Textus::Manifest::Resolver, enumerate: [
                                     { key: "bad.key", path: existing, manifest_entry: nil },
                                   ])

    expect do
      described_class.new(store: store_port).rebuild!(resolver: bad_resolver)
    end.to raise_error(NoMethodError)

    keys = store_port.connection.execute("SELECT key FROM entries ORDER BY key").map { |row| row["key"] }
    expect(keys).to eq(["knowledge.a", "raw.2026.06.19.url-example"])
  end
end
