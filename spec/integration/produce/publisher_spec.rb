require "spec_helper"

RSpec.describe Textus::Produce::Publisher do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(root, lanes: %w[knowledge feeds], manifest: <<~YAML)
      version: textus/4
      roles:
        - { name: automation, can: [converge] }
        - { name: human, can: [author] }
      lanes:
        - { name: knowledge, kind: canon }
        - { name: feeds, kind: machine }
      entries:
        - { key: knowledge.leaf, path: knowledge/leaf.md, lane: knowledge, kind: leaf }
        - key: feeds.generated
          kind: produced
          path: feeds/generated.json
          lane: feeds
          source: { from: external, command: "true", sources: [] }
    YAML
  end

  let(:call) { Textus::Value::Call.build(role: "automation") }

  describe "textus_link helper in templates" do
    let(:store_with_links) do
      store_from_manifest(root, lanes: %w[knowledge artifacts], manifest: <<~YAML)
        version: textus/4
        roles:
          - { name: human,      can: [author] }
          - { name: automation, can: [converge] }
        lanes:
          - { name: knowledge, kind: canon }
          - { name: artifacts, kind: machine }
        entries:
          - key: artifacts.reference.lanes
            lane: artifacts
            kind: produced
            format: json
            source: { from: external, command: "true", sources: [] }
            publish:
              - { to: docs/reference/lanes.md, template: guide.erb }
          - key: artifacts.how-to.guide
            lane: artifacts
            kind: produced
            format: json
            source: { from: external, command: "true", sources: [] }
            publish:
              - { to: docs/how-to/guide.md }
      YAML
    end

    before do
      container = store_with_links.container
      data_path = File.join(container.root, "data/artifacts/reference/lanes.json")
      FileUtils.mkdir_p(File.dirname(data_path))
      File.write(data_path, JSON.generate({ "_meta" => {}, "title" => "Lanes" }))
      tpl_path = File.join(container.root, "templates/guide.erb")
      FileUtils.mkdir_p(File.dirname(tpl_path))
      File.write(tpl_path, "# <%= title %>\nSee also: [guide](<%= textus_link(\"artifacts.how-to.guide\") %>)\n")
    end

    it "resolves textus_link to a relative path in the rendered output" do
      Textus::Produce::Publisher.call(
        container: store_with_links.container,
        call: Textus::Value::Call.build(role: "automation"),
        key: "artifacts.reference.lanes",
      )
      output_path = File.join(File.dirname(store_with_links.container.root), "docs/reference/lanes.md")
      expect(File.read(output_path)).to include("[guide](../how-to/guide.md)")
    end
  end

  describe ".call" do
    it "returns nil without publishing when entry has no publish targets" do
      result = described_class.call(
        container: store.container,
        call: call,
        key: "feeds.generated",
      )
      expect(result).to be_nil
    end

    it "returns nil without publishing when the entry file does not exist" do
      allow(store.container.file_store).to receive(:exists?).and_return(false)
      result = described_class.call(
        container: store.container,
        call: call,
        key: "feeds.generated",
      )
      expect(result).to be_nil
    end
  end
end
