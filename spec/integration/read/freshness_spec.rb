require "spec_helper"
require "time"

RSpec.describe Textus::Read::Freshness do
  include_context "textus_store_fixture"

  # knowledge.doc / knowledge.stale are intake entries with a source.ttl (the
  # :refresh signal); identity.note has no source.ttl and no retention rule, so
  # it is :no_policy. Intake age basis is the envelope's last_fetched_at (ADR 0093).
  let!(:store) do
    store_from_manifest(
      root,
      lanes: %w[knowledge identity],
      files: { "hooks/noop.rb" => "" },
      manifest: <<~YAML,
        version: textus/3
        lanes:
          - { name: knowledge, kind: machine }
          - { name: identity,   kind: canon }
        entries:
          - { key: knowledge.doc,   path: data/knowledge/doc.md,   lane: knowledge, kind: produced, source: { from: fetch, handler: noop, ttl: 1h } }

          - { key: knowledge.stale, path: data/knowledge/stale.md, lane: knowledge, kind: produced, source: { from: fetch, handler: noop, ttl: 1s } }

          - { key: identity.note,    path: identity/note.md,    lane: identity, kind: leaf}
      YAML
    )
  end

  def write_envelope(rel, last_fetched_at:)
    path = File.join(root, "data", rel)
    File.write(path, <<~MD)
      ---
      name: doc
      last_fetched_at: "#{last_fetched_at}"
      ---
      body
    MD
  end

  it "returns one row per manifest entry with :status, :key, :lane" do
    write_envelope("knowledge/doc.md",   last_fetched_at: Time.now.utc.iso8601)
    write_envelope("knowledge/stale.md", last_fetched_at: (Time.now.utc - 3600).iso8601)

    ops = store.as("human")
    rows = ops.freshness

    keys = rows.map { |r| r[:key] }
    expect(keys).to contain_exactly("knowledge.doc", "knowledge.stale", "identity.note")

    expect(rows).to all(include(:status, :key, :lane))

    by_key = rows.to_h { |r| [r[:key], r] }
    expect(by_key["knowledge.doc"][:status]).to eq(:fresh)
    expect(by_key["knowledge.stale"][:status]).to eq(:expired)
    expect(by_key["identity.note"][:status]).to eq(:no_policy)
  end

  it "filters by zone" do
    ops = store.as("human")
    rows = ops.freshness(lane: "identity")

    expect(rows.map { |r| r[:key] }).to eq(["identity.note"])
  end

  it "filters by prefix" do
    ops = store.as("human")
    rows = ops.freshness(prefix: "knowledge")

    expect(rows.map { |r| r[:key] }).to contain_exactly("knowledge.doc", "knowledge.stale")
  end

  it "reports :expired when policy exists but envelope is absent (never recorded)" do
    ops = store.as("human")
    rows = ops.freshness(prefix: "knowledge.doc")
    expect(rows.first[:status]).to eq(:expired)
    expect(rows.first[:next_due_at]).to be_nil
  end

  it "computes :next_due_at as last_fetched_at + ttl when both are present" do
    t = Time.utc(2026, 1, 1, 12, 0, 0)
    write_envelope("knowledge/doc.md", last_fetched_at: t.iso8601)
    ops = store.as("human")
    rows = ops.freshness(prefix: "knowledge.doc")
    expect(Time.parse(rows.first[:next_due_at])).to eq(t + 3600)
  end
end
