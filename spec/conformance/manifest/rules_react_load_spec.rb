require "spec_helper"

RSpec.describe "rules.react manifest load" do
  include_context "textus_store_fixture"

  def load(manifest)
    store_from_manifest(root, zones: %w[knowledge], manifest: manifest).manifest
  end

  it "loads react with allowed keys" do
    manifest = load(<<~YAML)
      version: textus/3
      zones: [{ name: knowledge, kind: canon }]
      entries: [{ key: knowledge.a, path: knowledge/a.md, zone: knowledge, kind: leaf }]
      rules:
        - match: "knowledge.*"
          react:
            on: [entry.written, schedule.tick]
            do: materialize
            scope: { prefix: knowledge }
            budget: { max_inflight: 2, timeout: 30s }
            idempotency: { by: [do, scope] }
            observe: [jobs.enqueued]
            priority: high
    YAML

    react = manifest.rules.for("knowledge.a").react
    expect(react).to be_a(Textus::Domain::Policy::React)
    expect(react.to_h["do"]).to eq("materialize")
  end

  it "rejects react.ttl to avoid ttl conflicts" do
    expect { load(<<~YAML) }.to raise_error(Textus::BadManifest, /react\.ttl.*invalid/i)
      version: textus/3
      zones: [{ name: knowledge, kind: canon }]
      entries: [{ key: knowledge.a, path: knowledge/a.md, zone: knowledge, kind: leaf }]
      rules:
        - match: "knowledge.*"
          react: { on: [schedule.tick], do: refresh_data, ttl: 5m }
    YAML
  end
end
