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
      version: textus/3
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
    expect(env["protocol"]).to eq("textus/3")
    expect(env["store_root"]).to eq(root)
  end

  it "lists lanes with writers and purposes derived from manifest desc:" do
    env = described_class.build(container: store.container)
    names = env["lanes"].map { |z| z["name"] }
    expect(names).to contain_exactly("identity", "knowledge", "artifacts", "proposals")
    identity = env["lanes"].find { |z| z["name"] == "identity" }
    expect(identity["writers"]).to eq(["human"])
    expect(identity["purpose"]).to include("human-only")

    knowledge = env["lanes"].find { |z| z["name"] == "knowledge" }
    expect(knowledge["writers"]).to eq(["human"])
    expect(knowledge).to have_key("purpose")

    proposals = env["lanes"].find { |z| z["name"] == "proposals" }
    expect(proposals["writers"]).to contain_exactly("human", "agent")

    artifacts = env["lanes"].find { |z| z["name"] == "artifacts" }
    expect(artifacts["writers"]).to eq(["automation"])
  end

  it "omits purpose for unknown lane names" do
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
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

  it "omits index_key when artifacts.index does not exist" do
    env = described_class.build(container: store.container)
    expect(env).not_to have_key("index_key")
  end

  it "includes index_key when artifacts.index file exists" do
    FileUtils.mkdir_p(File.join(root, "data/artifacts"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      roles:
        - { name: human,      can: [author, propose] }
        - { name: automation, can: [converge] }
      lanes:
        - { name: artifacts, kind: machine }
        - { name: proposals, kind: queue }
      entries:
        - key: artifacts.index
          kind: produced
          path: artifacts/index.json
          lane: artifacts
          owner: automation:auto
          source: { from: external, command: "true", sources: [] }
    YAML
    File.write(File.join(root, "data/artifacts/index.json"), "{}")
    s = Textus::Store.new(root)
    env = described_class.build(container: s.container)
    expect(env["index_key"]).to eq("artifacts.index")
  end

  it "includes agent_protocol with recipes and role_resolution" do
    env = described_class.build(container: store.container)
    expect(env["agent_protocol"]).to include("recipes", "role_resolution")
  end

  it "omits orientation when artifacts.orientation does not exist" do
    env = described_class.build(container: store.container)
    expect(env).not_to have_key("orientation")
  end

  it "omits context when knowledge.boot does not exist" do
    env = described_class.build(container: store.container)
    expect(env).not_to have_key("context")
  end

  it "does not include entries, workflows, cli_verbs, write_flows, or docs" do
    env = described_class.build(container: store.container)
    expect(env.keys).not_to include("entries", "workflows", "cli_verbs", "write_flows", "docs")
  end

  describe "agent_protocol block" do
    it "includes envelope_shape, role_resolution, and recipes" do
      result = Textus::Boot.build(container: store.container)
      expect(result).to have_key("agent_protocol")
      block = result["agent_protocol"]
      expect(block).to have_key("envelope_shape")
      expect(block).to have_key("role_resolution")
      expect(block["recipes"].keys).to contain_exactly("read", "write", "propose", "drain")
    end

    it "does not change the wire protocol field" do
      result = Textus::Boot.build(container: store.container)
      expect(result["protocol"]).to eq("textus/3")
    end

    it "is omitted from per-recipe output by default (no example field)" do
      result = Textus::Boot.build(container: store.container)
      result["agent_protocol"]["recipes"].each_value do |r|
        expect(r).not_to have_key("example")
      end
    end
  end

  describe "contract_etag (ADR 0084)" do
    it "the full envelope carries a sha256 contract_etag" do
      out = Textus::Boot.build(container: store.container)
      expect(out["contract_etag"]).to match(/\Asha256:/)
    end
  end

  describe "role_resolution" do
    it "falls back to default role names when roles: block is omitted" do
      yaml = <<~YAML
        version: textus/3
        lanes:
          - { name: identity, kind: canon }
          - { name: proposals,   kind: queue }
          - { name: artifacts,   kind: machine }
        entries: []
      YAML
      s = store_from_manifest(root, manifest: yaml)
      env = described_class.build(container: s.container)
      roles = env["agent_protocol"]["role_resolution"]["roles"]
      expect(roles).to contain_exactly("human", "agent", "automation")
    end
  end

  it "is callable through the CLI as JSON" do
    out = StringIO.new
    err = StringIO.new
    code = Textus::Surfaces::CLI.run(["boot", "--output=json"],
                                     stdin: StringIO.new(""), stdout: out, stderr: err, cwd: tmp)
    expect(code).to eq(0)
    parsed = JSON.parse(out.string)
    expect(parsed["protocol"]).to eq("textus/3")
    expect(parsed["lanes"].length).to eq(4)
    expect(parsed).not_to have_key("index_key")
  end
end
