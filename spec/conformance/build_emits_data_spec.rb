require "spec_helper"

RSpec.describe "build emits data, not a render (ADR 0094)" do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(root, lanes: %w[knowledge artifacts],
                              manifest: <<~YAML,
                                version: textus/3
                                lanes:
                                  - { name: knowledge, kind: canon }
                                  - { name: artifacts, kind: machine }
                                entries:
                                  - { key: knowledge.a, path: data/knowledge/a.md, lane: knowledge, kind: leaf }
                                  - key: artifacts.data
                                    kind: produced
                                    path: data/artifacts/data.json
                                    lane: artifacts
                                    source: { from: derive, select: [knowledge.a], pluck: [key] }
                              YAML
                              files: { "data/knowledge/a.md" => "---\ntitle: A\n---\nbody\n" })
  end

  it "stores the projection data as json (no template consulted)" do
    Textus::Produce::Engine.new(container: store.container, call: test_ctx(role: "automation"))
                            .call(keys: ["artifacts.data"])
    raw = File.read(File.join(root, "data/artifacts/data.json"))
    expect(raw).to include("knowledge.a")
    expect { JSON.parse(raw) }.not_to raise_error
  end
end
