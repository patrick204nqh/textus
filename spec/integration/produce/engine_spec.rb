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
        - { key: knowledge.foo, path: knowledge/foo.md, lane: knowledge, kind: leaf}
        - key: artifacts.feeds.github.repos
          kind: produced
          path: feeds/repos.md
          lane: feeds
          source: { from: external, command: "true", sources: [] }
    YAML
  end

  it "completes as a no-op when no workflow matches and entry has no publish targets" do
    result = described_class.converge(
      container: store.container,
      call: Textus::Call.build(role: "automation"),
      keys: ["artifacts.feeds.github.repos"],
    )
    expect(result[:completed]).to include("artifacts.feeds.github.repos")
    expect(result[:failed]).to be_empty
  end

  it "converges a key when a workflow is registered" do
    fetched = []
    defn = Textus::Workflow::DSL::Definition.new("test")
    defn.match("artifacts.feeds.github.*")
    defn.step(:fetch) do |_data, ctx|
      fetched << ctx.key
      { content: ["item"] }
    end
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
