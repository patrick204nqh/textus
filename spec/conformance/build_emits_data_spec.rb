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
                                  - { key: knowledge.a, path: knowledge/a.md, lane: knowledge, kind: leaf }
                                  - key: artifacts.data
                                    kind: produced
                                    path: artifacts/data.json
                                    lane: artifacts
                                    source: { from: external, command: "make", sources: [] }
                              YAML
                              files: { "data/knowledge/a.md" => "---\ntitle: A\n---\nbody\n" })
  end

  it "completes without error (derive data produced via workflow in full system)" do
    result = Textus::Produce::Engine.new(container: store.container, call: test_ctx(role: "automation"))
                                    .run(["artifacts.data"])
    expect(result[:failed]).to be_empty
    expect(result[:completed]).to include("artifacts.data")
  end
end
