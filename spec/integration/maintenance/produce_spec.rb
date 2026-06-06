require "spec_helper"

RSpec.describe Textus::Maintenance::Produce do
  subject(:produce) { described_class.new(container: store.container, call: call) }

  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(
      root,
      zones: %w[knowledge feeds],
      files: {
        "zones/knowledge/a.md" => "---\ntitle: A\n---\nbody\n",
        "templates/catalog.mustache" => "{{#entries}}{{title}}\n{{/entries}}",
      },
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
              project: { select: "knowledge", pluck: [title] }
          - key: feeds.ext
            kind: derived
            path: feeds/ext.md
            zone: feeds
            source: { from: command, command: "true", sources: ["knowledge.*"] }
      YAML
    )
  end

  let(:call) { test_ctx(role: "automation") }

  it "produces a derived template entry (renders to disk)" do
    result = produce.call(keys: ["feeds.catalog"])
    expect(result[:produced]).to include("feeds.catalog")
    expect(File.read(File.join(root, "zones/feeds/catalog.md"))).to include("A")
  end

  it "skips an external (command) source" do
    result = produce.call(keys: ["feeds.ext"])
    expect(result[:skipped]).to include("feeds.ext")
    expect(result[:produced]).not_to include("feeds.ext")
  end
end
