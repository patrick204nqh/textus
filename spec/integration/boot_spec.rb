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
          path: data/knowledge/notes
          lane: knowledge
          nested: true
        - key: artifacts.feed
          kind: produced
          path: data/artifacts/feed.md
          lane: artifacts
          owner: automation:local
          source: { from: external, command: "make", sources: [] }
        - key: artifacts.report
          kind: produced
          path: data/artifacts/report.json
          lane: artifacts
          owner: automation:auto
          source: { from: external, command: "make", sources: [] }
          publish:
            - { to: REPORT.md, template: report.mustache }
    YAML

    File.write(File.join(root, "templates/report.mustache"), "ok\n")
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

  it "lists entries with publish_to and nested flags" do
    env = described_class.build(container: store.container)
    by_key = env["entries"].to_h { |e| [e["key"], e] }

    expect(by_key["identity.self"]).not_to have_key("derived")
    expect(by_key["identity.self"]).not_to have_key("intake")

    expect(by_key["artifacts.report"]["publish_to"]).to eq(["REPORT.md"])
    expect(by_key["artifacts.report"]).not_to have_key("publish_each")

    expect(by_key["knowledge.notes"]["nested"]).to be true
  end

  it "lists registered workflows as an array" do
    env = described_class.build(container: store.container)
    expect(env["workflows"]).to be_an(Array)
    expect(env["workflows"]).to all(include("name", "match"))
  end

  it "includes verbatim write_flows and cli_verbs" do
    env = described_class.build(container: store.container)
    expect(env["write_flows"]).to include("human", "agent", "automation")
    expect(env["write_flows"]["agent"]).to include("proposal:")

    # human holds [author, propose] → its write_flow joins both guidance
    # strings (author's 'textus put' + propose's 'proposal:') with ' / '.
    expect(env["write_flows"]["human"]).to include("textus put").and include(" / ").and include("proposal:")

    names = env["cli_verbs"].map { |v| v["name"] }
    expect(names).to include("boot", "list", "get", "put", "accept", "drain", "doctor")
    expect(names).not_to include("build") # build verb removed in ADR 0087
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

  describe "backward compatibility" do
    it "keeps every pre-0.12.3 top-level key with its original shape" do
      result = Textus::Boot.build(container: store.container)
      expect(result["protocol"]).to be_a(String).and eq("textus/3")
      expect(result["store_root"]).to be_a(String)
      expect(result["lanes"]).to be_a(Array)
      expect(result["entries"]).to be_a(Array)
      expect(result["workflows"]).to be_a(Array)
      expect(result["write_flows"]).to be_a(Hash)
      expect(result["cli_verbs"]).to be_a(Array)
      expect(result["docs"]).to be_a(Hash)
    end
  end

  describe "lean projection + contract_etag (ADR 0084)" do
    it "the full envelope carries a sha256 contract_etag" do
      out = Textus::Boot.build(container: store.container)
      expect(out["contract_etag"]).to match(/\Asha256:/)
    end

    it "lean keeps orientation essentials and drops the heavy sections" do
      out = Textus::Boot.build(container: store.container, lean: true)
      expect(out).to include("protocol", "store_root", "lanes", "agent_quickstart", "contract_etag")
      expect(out).not_to include("entries", "workflows", "cli_verbs", "agent_protocol", "write_flows")
    end
  end

  describe "write_flows role resolution" do
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
      flows = env["write_flows"]
      expect(flows.keys).to contain_exactly("human", "agent", "automation")

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
    expect(parsed["cli_verbs"]).to be_an(Array)
  end

  it "the CLI --lean flag yields the lean envelope" do
    out = StringIO.new
    err = StringIO.new
    code = Textus::Surfaces::CLI.run(["boot", "--lean", "--output=json"],
                                     stdin: StringIO.new(""), stdout: out, stderr: err, cwd: tmp)
    expect(code).to eq(0)
    parsed = JSON.parse(out.string)
    expect(parsed).to include("agent_quickstart", "contract_etag")
    expect(parsed).not_to have_key("entries")
  end
end
