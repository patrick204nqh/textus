require "spec_helper"
require "stringio"

RSpec.describe Textus::Boot do
  include_context "textus_store_fixture"

  before do
    FileUtils.mkdir_p(File.join(root, "data/identity"))
    FileUtils.mkdir_p(File.join(root, "data/knowledge/notes"))
    FileUtils.mkdir_p(File.join(root, "data/artifacts"))
    FileUtils.mkdir_p(File.join(root, "data/proposals"))
    FileUtils.mkdir_p(File.join(root, "schemas"))
    FileUtils.mkdir_p(File.join(root, "templates"))

    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/4
      roles:
        - { name: human,      can: [author, propose] }
        - { name: agent,      can: [propose] }
        - { name: automation, can: [converge] }
      lanes:
        - { name: identity,  kind: canon,   desc: "slow-changing identity; human-only writes" }
        - { name: knowledge, kind: canon,   desc: "active project state; humans, AI, and scripts share this surface" }
        - { name: artifacts, kind: machine, desc: "computed outputs + external feeds" }
        - { name: proposals, kind: queue }
      entries:
        - { key: identity.self, path: identity/self.md, lane: identity, owner: human:self, kind: leaf}

        - key: knowledge.notes
          kind: nested
          path: knowledge/notes
          lane: knowledge
          nested: true
        - key: artifacts.feed
          kind: produced
          path: artifacts/feed.md
          lane: artifacts
          owner: automation:local
          source: { from: external, command: "make", sources: [] }
        - key: artifacts.report
          kind: produced
          path: artifacts/report.json
          lane: artifacts
          owner: automation:auto
          source: { from: external, command: "make", sources: [] }
          publish:
            - { to: REPORT.md, template: report.erb }
    YAML

    File.write(File.join(root, "templates/report.erb"), "ok\n")
  end

  let(:store) { Textus::Store.new(root) }

  it "returns an envelope with protocol + store_root" do
    env = described_class.build(container: store.container)
    expect(env["protocol"]).to eq("textus/4")
    expect(env["store_root"]).to eq(root)
  end

  it "omits purpose for unknown lane names" do
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/4
      lanes:
        - { name: identity, kind: canon }
        - { name: weird,    kind: canon }
      entries:
        - { key: identity.self, path: identity/self.md, lane: identity, kind: leaf}

    YAML
    s = Textus::Store.new(root)
    env = described_class.build(container: s.container)
    weird = env["lanes"].find { |z| z["name"] == "weird" }
    expect(weird).not_to have_key("purpose")
  end

  it "never includes index_key" do
    env = described_class.build(container: store.container)
    expect(env).not_to have_key("index_key")
  end

  it "does not include entries, workflows, cli_verbs, write_flows, or docs" do
    env = described_class.build(container: store.container)
    expect(env.keys).not_to include("entries", "workflows", "cli_verbs", "write_flows", "docs")
  end
end
