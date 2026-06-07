require "spec_helper"

RSpec.describe "publish per target (ADR 0094)" do
  include_context "textus_store_fixture"

  describe "one publish path renders per target" do
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
                                      kind: produced
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
      Textus::Produce::Engine.new(container: store.container, call: test_ctx(role: "automation"))
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

  describe "json leaf verbatim publish (Base#external?)" do
    let(:store) do
      store_from_manifest(root, zones: %w[knowledge],
                                manifest: <<~YAML,
                                  version: textus/3
                                  zones:
                                    - { name: knowledge, kind: canon }
                                  entries:
                                    - key: knowledge.cfg
                                      kind: leaf
                                      path: knowledge/cfg.json
                                      zone: knowledge
                                      publish:
                                        - { to: out.json }
                                YAML
                                files: {
                                  "zones/knowledge/cfg.json" => %({"_meta":{"key":"knowledge.cfg"},"content":{"a":1}}\n),
                                })
    end

    it "publishes a json leaf verbatim without crashing (Base#external?)" do
      expect do
        Textus::Produce::Engine.new(container: store.container, call: test_ctx(role: "automation"))
                               .call(keys: ["knowledge.cfg"])
      end.not_to raise_error

      published = JSON.parse(File.read(File.join(tmp, "out.json")))
      expect(published).not_to have_key("_meta")
      expect(published).to eq("content" => { "a" => 1 })
    end
  end
end
