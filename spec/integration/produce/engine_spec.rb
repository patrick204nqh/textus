require "spec_helper"

RSpec.describe Textus::Produce::Engine do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(root, lanes: %w[knowledge feeds], manifest: <<~YAML)
      version: textus/3
      roles:
        - { name: automation, can: [converge] }
        - { name: human, can: [author] }
      lanes:
        - { name: knowledge, kind: canon }
        - { name: feeds, kind: machine }
      entries:
        - { key: knowledge.foo, path: data/knowledge/foo.md, lane: knowledge, kind: leaf}
        - key: artifacts.feeds.github.repos
          kind: produced
          path: data/feeds/repos.md
          lane: feeds
          source: { from: external, command: "true", sources: [] }
    YAML
  end

  it "raises Workflow::NotFound when no workflow matches the key" do
    result = described_class.converge(
      container: store.container,
      call: Textus::Call.build(role: "automation"),
      keys: ["artifacts.feeds.github.repos"],
    )
    expect(result[:failed].first[:error]).to include("no workflow matches")
  end

  it "converges a key when a workflow is registered" do
    fetched = []
    defn = Textus::Workflow::DSL::Definition.new("test")
    defn.match("artifacts.feeds.github.*")
    defn.step(:fetch) { |data, ctx| fetched << ctx.key; { content: ["item"] } }
    store.container.workflows.register(defn)

    result = described_class.converge(
      container: store.container,
      call: Textus::Call.build(role: "automation"),
      keys: ["artifacts.feeds.github.repos"],
    )
    expect(result[:completed]).to include("artifacts.feeds.github.repos")
    expect(fetched).to eq(["artifacts.feeds.github.repos"])
  end
end
