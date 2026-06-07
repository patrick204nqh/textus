require "spec_helper"

RSpec.describe "build emits data, not a render (ADR 0094)" do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(root, zones: %w[knowledge artifacts],
                              manifest: <<~YAML,
                                version: textus/3
                                zones:
                                  - { name: knowledge, kind: canon }
                                  - { name: artifacts, kind: machine }
                                entries:
                                  - { key: knowledge.a, path: knowledge/a.md, zone: knowledge, kind: leaf }
                                  - key: artifacts.data
                                    kind: derived
                                    path: artifacts/data.json
                                    zone: artifacts
                                    source: { from: project, select: [knowledge.a], pluck: [key] }
                              YAML
                              files: { "zones/knowledge/a.md" => "---\ntitle: A\n---\nbody\n" })
  end

  it "stores the projection data as json (no template consulted)" do
    Textus::Maintenance::Produce.new(container: store.container, call: test_ctx(role: "automation"))
                                .call(keys: ["artifacts.data"])
    raw = File.read(File.join(root, "zones/artifacts/data.json"))
    expect(raw).to include("knowledge.a")
    expect { JSON.parse(raw) }.not_to raise_error
  end
end
