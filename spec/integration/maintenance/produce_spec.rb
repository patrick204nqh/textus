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

  describe "per-key failure isolation (ADR 0087 §5)" do
    let(:store) do
      store_from_manifest(
        root,
        zones: %w[working],
        files: {
          "zones/working/skills/s/commands.md" => "# c\n",
          "zones/knowledge/a.md" => "---\ntitle: A\n---\nbody\n",
          "templates/catalog.mustache" => "{{#entries}}{{title}}\n{{/entries}}",
        },
        manifest: <<~YAML,
          version: textus/3
          zones:
            - { name: working, kind: canon }
            - { name: knowledge, kind: canon }
            - { name: feeds, kind: machine }
          entries:
            - { key: knowledge.a, path: knowledge/a.md, zone: knowledge, kind: leaf }
            - key: working.bad
              kind: nested
              path: working/skills
              zone: working
              schema: null
              nested: true
              publish: { tree: "../outside" }
            - key: feeds.catalog
              kind: derived
              path: feeds/catalog.md
              zone: feeds
              source: { from: template, template: catalog.mustache, project: { select: "knowledge", pluck: [title] } }
        YAML
      )
    end

    it "lands a failing key in [:failed] while a sibling still produces" do
      result = produce.call(keys: ["working.bad", "feeds.catalog"])
      failure = result[:failed].find { |f| f["key"] == "working.bad" }
      expect(failure["error"]).to match(/escapes repo root/)
      expect(result[:produced]).to include("feeds.catalog")
    end
  end

  describe ".converge failure isolation" do
    # A manifest where no role holds the `reconcile` capability: build_actor_call
    # raises a Textus::UsageError that escapes Produce#call (it is outside the
    # per-key rescue). converge must swallow it and publish :materialize_failed.
    it "does not raise and publishes :materialize_failed" do
      fired = []
      store.container.events.on(:materialize_failed, :probe) { |error:, **| fired << error }

      # Force build_actor_call to fail (no reconcile actor at call time) so a
      # Textus::Error escapes Produce#call — the path .converge must isolate.
      allow(store.container.manifest.policy).to receive(:actor_for).with("reconcile").and_return(nil)

      expect do
        described_class.converge(container: store.container, call: call, keys: ["feeds.catalog"])
      end.not_to raise_error
      expect(fired).not_to be_empty
      expect(fired.first).to match(/reconcile/)
    end
  end
end
