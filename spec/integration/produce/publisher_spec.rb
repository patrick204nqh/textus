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
