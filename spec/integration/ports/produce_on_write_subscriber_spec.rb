require "spec_helper"

RSpec.describe "produce-on-write (ADR 0093)" do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(root, zones: %w[knowledge feeds],
                              manifest: <<~YAML,
                                version: textus/3
                                zones:
                                  - { name: knowledge, kind: canon }
                                  - { name: feeds, kind: machine }
                                entries:
                                  - { key: knowledge.a, path: knowledge/a.md, zone: knowledge, kind: leaf }
                                  - key: feeds.catalog
                                    kind: derived
                                    path: feeds/catalog.md
                                    zone: feeds
                                    source:
                                      from: template
                                      template: catalog.mustache
                                      on_write: sync
                                      project: { select: "knowledge", pluck: [title] }
                              YAML
                              files: { "templates/catalog.mustache" => "{{#entries}}{{title}}\n{{/entries}}" })
  end

  it "sync source: a canon write leaves the dependent derived fresh on return" do
    store.as("human").put("knowledge.a", meta: { "title" => "Apple" }, body: "x\n")
    expect(File.read(File.join(root, "zones/feeds/catalog.md"))).to include("Apple")
  end
end
