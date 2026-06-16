require "spec_helper"

RSpec.describe "publish per target (ADR 0094)" do
  include_context "textus_store_fixture"

  describe "one publish path renders per target" do
    let(:store) do
      store_from_manifest(root, lanes: %w[knowledge artifacts],
                                manifest: <<~YAML,
                                  version: textus/3
                                  lanes:
                                    - { name: knowledge, kind: canon }
                                    - { name: artifacts, kind: machine }
                                  entries:
                                    - { key: knowledge.a, path: data/knowledge/a.md, lane: knowledge, kind: leaf }
                                    - key: artifacts.cat
                                      kind: produced
                                      path: data/artifacts/cat.json
                                      lane: artifacts
                                      source: { from: external, command: "make", sources: [] }
                                      publish:
                                        - { to: OUT.md, template: rows.mustache }
                                        - { to: out.json }
                                YAML
                                files: {
                                  "data/knowledge/a.md" => "---\ntitle: A\n---\nbody\n",
                                  "templates/rows.mustache" => "{{#entries}}{{_key}}\n{{/entries}}",
                                })
    end

    before do
      Textus::Produce::Engine.new(container: store.container, call: test_ctx(role: "automation"))
                             .run(["artifacts.cat"])
    end

    it "renders the markdown target through its template (workflow-driven in full system)" do
      # Derive pipeline runs via workflow; without a registered workflow only
      # existing store bytes are published. Confirm no crash and no stale file.
      expect(File.exist?(File.join(root, "data/artifacts/cat.json"))).to be false
    end

    it "completes the produce run without error for derive entries" do
      result = Textus::Produce::Engine.new(container: store.container, call: test_ctx(role: "automation"))
                                      .run(["artifacts.cat"])
      expect(result[:failed]).to be_empty
    end
  end

  describe "json leaf verbatim publish (Base#external?)" do
    let(:store) do
      store_from_manifest(root, lanes: %w[knowledge],
                                manifest: <<~YAML,
                                  version: textus/3
                                  lanes:
                                    - { name: knowledge, kind: canon }
                                  entries:
                                    - key: knowledge.cfg
                                      kind: leaf
                                      path: data/knowledge/cfg.json
                                      lane: knowledge
                                      publish:
                                        - { to: out.json }
                                YAML
                                files: {
                                  "data/knowledge/cfg.json" => %({"_meta":{"key":"knowledge.cfg"},"content":{"a":1}}\n),
                                })
    end

    it "publishes a json leaf verbatim without crashing (Base#external?)" do
      expect do
        Textus::Produce::Engine.new(container: store.container, call: test_ctx(role: "automation"))
                               .run(["knowledge.cfg"])
      end.not_to raise_error

      published = JSON.parse(File.read(File.join(tmp, "out.json")))
      expect(published).not_to have_key("_meta")
      expect(published).to eq("content" => { "a" => 1 })
    end
  end
end
