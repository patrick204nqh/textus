require "spec_helper"

RSpec.describe "one publish path renders per target (ADR 0094)" do
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
                                  - key: artifacts.cat
                                    kind: derived
                                    path: artifacts/cat.json
                                    zone: artifacts
                                    source: { from: project, select: [knowledge.a] }
                                    publish:
                                      - { to: OUT.md, template: rows.mustache }
                                      - { to: out.json }
                              YAML
                              files: {
                                "zones/knowledge/a.md" => "---\ntitle: A\n---\nbody\n",
                                "templates/rows.mustache" => "{{#entries}}{{_key}}\n{{/entries}}",
                              })
  end

  before do
    Textus::Maintenance::Produce.new(container: store.container, call: test_ctx(role: "automation"))
                                .call(keys: ["artifacts.cat"])
  end

  it "renders the markdown target through its template" do
    expect(File.read(File.join(tmp, "OUT.md"))).to include("knowledge.a")
  end

  it "publishes the json target as clean content (no textus _meta)" do
    published = JSON.parse(File.read(File.join(tmp, "out.json")))
    expect(published).not_to have_key("_meta")
    expect(published).to have_key("entries")
    expect(JSON.parse(File.read(File.join(root, "zones/artifacts/cat.json")))).to have_key("_meta")
  end
end
