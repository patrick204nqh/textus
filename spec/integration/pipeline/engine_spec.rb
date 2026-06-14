require "spec_helper"

RSpec.describe Textus::Pipeline::Engine do
  subject(:produce) { described_class.new(container: store.container, call: call) }

  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(
      root,
      lanes: %w[knowledge feeds],
      files: {
        "data/knowledge/a.md" => "---\ntitle: A\n---\nbody\n",
        "templates/catalog.mustache" => "{{#entries}}{{title}}\n{{/entries}}",
      },
      manifest: <<~YAML,
        version: textus/3
        lanes:
          - { name: knowledge, kind: canon }
          - { name: feeds, kind: machine }
        entries:
          - { key: knowledge.a, path: data/knowledge/a.md, lane: knowledge, kind: leaf }
          - key: feeds.catalog
            kind: produced
            path: data/feeds/catalog.json
            lane: feeds
            source:
              from: derive
              select: "knowledge"
              pluck: [title]
            publish:
              - { to: CATALOG.md, template: catalog.mustache }
          - key: feeds.ext
            kind: produced
            path: data/feeds/ext.md
            lane: feeds
            source: { from: external, command: "true", sources: ["knowledge.*"] }
      YAML
    )
  end

  let(:call) { test_ctx(role: "automation") }

  it "produces a derived projection (data to store, render to publish target)" do
    result = produce.call(keys: ["feeds.catalog"])
    expect(result[:produced]).to include("feeds.catalog")
    expect(File.read(File.join(root, "data/feeds/catalog.json"))).to include("A")
    expect(File.read(File.join(tmp, "CATALOG.md"))).to include("A")
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
        lanes: %w[working],
        files: {
          "data/working/skills/s/commands.md" => "# c\n",
          "data/knowledge/a.md" => "---\ntitle: A\n---\nbody\n",
          "templates/catalog.mustache" => "{{#entries}}{{title}}\n{{/entries}}",
        },
        manifest: <<~YAML,
          version: textus/3
          lanes:
            - { name: working, kind: canon }
            - { name: knowledge, kind: canon }
            - { name: feeds, kind: machine }
          entries:
            - { key: knowledge.a, path: data/knowledge/a.md, lane: knowledge, kind: leaf }
            - key: working.bad
              kind: nested
              path: working/skills
              lane: working
              schema: null
              nested: true
              publish:
                - { tree: "../outside" }
            - key: feeds.catalog
              kind: produced
              path: data/feeds/catalog.json
              lane: feeds
              source: { from: derive, select: "knowledge", pluck: [title] }
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
    # A manifest where no role holds the `converge` capability: build_actor_call
    # raises a Textus::UsageError that escapes Produce#call (it is outside the
    # per-key rescue). converge must swallow it and publish :produce_failed.
    it "does not raise and publishes :produce_failed" do
      fired = []
      store.container.steps.on(:produce_failed, :probe) { |error:, **| fired << error }

      # Force build_actor_call to fail (no converge actor at call time) so a
      # Textus::Error escapes Produce#call — the path .converge must isolate.
      allow(store.container.manifest.policy).to receive(:actor_for).with("converge").and_return(nil)

      expect do
        described_class.converge(container: store.container, call: call, keys: ["feeds.catalog"])
      end.not_to raise_error
      expect(fired).not_to be_empty
      expect(fired.first).to match(/converge/)
    end
  end
end
