require "spec_helper"
require "time"

RSpec.describe Textus::Read::Freshness do
  include_context "textus_store_fixture"

  let!(:store) do
    store_from_manifest(
      root,
      zones: %w[working identity],
      files: { "hooks/noop.rb" => "" },
      manifest: <<~YAML,
        version: textus/3
        zones:
          - { name: working, kind: canon }
          - { name: identity,   kind: canon }
        entries:
          - { key: working.doc,   path: working/doc.md,   zone: working, kind: leaf}

          - { key: working.stale, path: working/stale.md, zone: working, kind: leaf}

          - { key: identity.note,    path: identity/note.md,    zone: identity, kind: leaf}

        rules:
          - match: working.doc
            fetch: { ttl: 1h, on_stale: warn }
          - match: working.stale
            fetch: { ttl: 1s, on_stale: warn }
      YAML
    )
  end

  def write_envelope(rel, last_fetched_at:)
    path = File.join(root, "zones", rel)
    File.write(path, <<~MD)
      ---
      name: doc
      last_fetched_at: "#{last_fetched_at}"
      ---
      body
    MD
  end

  it "returns one row per manifest entry with :status, :key, :zone" do
    write_envelope("working/doc.md",   last_fetched_at: Time.now.utc.iso8601)
    write_envelope("working/stale.md", last_fetched_at: (Time.now.utc - 3600).iso8601)

    ops = store.as("human")
    rows = ops.freshness

    keys = rows.map { |r| r[:key] }
    expect(keys).to contain_exactly("working.doc", "working.stale", "identity.note")

    expect(rows).to all(include(:status, :key, :zone))

    by_key = rows.to_h { |r| [r[:key], r] }
    expect(by_key["working.doc"][:status]).to eq(:fresh)
    expect(by_key["working.stale"][:status]).to eq(:stale)
    expect(by_key["identity.note"][:status]).to eq(:no_policy)
  end

  it "filters by zone" do
    ops = store.as("human")
    rows = ops.freshness(zone: "identity")

    expect(rows.map { |r| r[:key] }).to eq(["identity.note"])
  end

  it "filters by prefix" do
    ops = store.as("human")
    rows = ops.freshness(prefix: "working")

    expect(rows.map { |r| r[:key] }).to contain_exactly("working.doc", "working.stale")
  end

  it "reports :never_fetched when policy exists but envelope is absent" do
    ops = store.as("human")
    rows = ops.freshness(prefix: "working.doc")
    expect(rows.first[:status]).to eq(:never_fetched)
    expect(rows.first[:next_due_at]).to be_nil
  end

  it "computes :next_due_at as last_fetched_at + ttl when both are present" do
    t = Time.utc(2026, 1, 1, 12, 0, 0)
    write_envelope("working/doc.md", last_fetched_at: t.iso8601)
    ops = store.as("human")
    rows = ops.freshness(prefix: "working.doc")
    expect(Time.parse(rows.first[:next_due_at])).to eq(t + 3600)
  end
end
