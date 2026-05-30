require "spec_helper"
require "tmpdir"
require "fileutils"
require "json"
require "stringio"

RSpec.describe Textus::Boot do
  include_context "textus_store_fixture"

  before do
    FileUtils.mkdir_p(File.join(root, "zones/identity"))
    FileUtils.mkdir_p(File.join(root, "zones/working/notes"))
    FileUtils.mkdir_p(File.join(root, "zones/intake"))
    FileUtils.mkdir_p(File.join(root, "zones/output"))
    FileUtils.mkdir_p(File.join(root, "zones/review"))
    FileUtils.mkdir_p(File.join(root, "schemas"))
    FileUtils.mkdir_p(File.join(root, "templates"))
    FileUtils.mkdir_p(File.join(root, "hooks"))

    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      roles:
        - { name: human,      can: [accept, propose] }
        - { name: agent,      can: [propose] }
        - { name: automation, can: [fetch, build] }
      zones:
        - { name: identity, kind: origin }
        - { name: working,  kind: origin }
        - { name: intake,   kind: quarantine }
        - { name: review,   kind: queue }
        - { name: output,   kind: derived }
      entries:
        - { key: identity.self, path: identity/self.md, zone: identity, schema: null, owner: human:self, kind: leaf}

        - key: working.notes
          kind: nested
          path: working/notes
          zone: working
          schema: null
          nested: true
        - key: intake.feed
          kind: intake
          path: intake/feed.md
          zone: intake
          owner: automation:local
          intake:
            handler: demo-action
            config: { foo: 1 }
        - key: output.report
          kind: derived
          path: output/report.md
          zone: output
          owner: automation:auto
          compute:
            kind: projection
            select: [working.notes]
            pluck: "*"
          template: report.mustache
          publish_to: [REPORT.md]
    YAML

    File.write(File.join(root, "templates/report.mustache"), "ok\n")

    File.write(File.join(root, "hooks/exts.rb"), <<~RUBY)
      Textus.hook do |reg|
        reg.on(:resolve_intake, :"demo-action") { |caps:, config:, args:| { _meta: {}, body: "" } }
        reg.on(:resolve_intake, :zebra)         { |caps:, config:, args:| { _meta: {}, body: "" } }
        reg.on(:resolve_intake, :apple)         { |caps:, config:, args:| { _meta: {}, body: "" } }
        reg.on(:transform_rows, :rank_by_recency) { |caps:, rows:, config:| rows }
        reg.on(:transform_rows, :alpha)           { |caps:, rows:, config:| rows }
        reg.on(:build_completed, :stamp_log)        { |**| }
        reg.on(:validate, :smoke)            { |caps:| [] }
      end
    RUBY
  end

  def store
    @store ||= Textus::Store.new(root)
  end

  def session_for(s)
    s.as(Textus::Role::DEFAULT)
  end

  it "returns an envelope with protocol + store_root" do
    env = described_class.build(container: store.container)
    expect(env["protocol"]).to eq("textus/3")
    expect(env["store_root"]).to eq(root)
  end

  it "lists zones with writers and purposes for known zones" do
    env = described_class.build(container: store.container)
    names = env["zones"].map { |z| z["name"] }
    expect(names).to contain_exactly("identity", "working", "intake", "review", "output")
    identity = env["zones"].find { |z| z["name"] == "identity" }
    expect(identity["writers"]).to eq(["human"])
    expect(identity["purpose"]).to include("human-only")

    working = env["zones"].find { |z| z["name"] == "working" }
    expect(working["writers"]).to eq(["human"])
    expect(working).to have_key("purpose")

    intake = env["zones"].find { |z| z["name"] == "intake" }
    expect(intake["writers"]).to eq(["automation"])

    review = env["zones"].find { |z| z["name"] == "review" }
    expect(review["writers"]).to contain_exactly("human", "agent")

    output = env["zones"].find { |z| z["name"] == "output" }
    expect(output["writers"]).to eq(["automation"])
  end

  it "omits purpose for unknown zone names" do
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: identity, kind: origin }
        - { name: weird,    kind: origin }
      entries:
        - { key: identity.self, path: identity/self.md, zone: identity, schema: null, kind: leaf}

    YAML
    s = Textus::Store.new(root)
    env = described_class.build(container: s.container)
    weird = env["zones"].find { |z| z["name"] == "weird" }
    expect(weird).not_to have_key("purpose")
  end

  it "lists entries with derived, intake, publish_to flags" do
    env = described_class.build(container: store.container)
    by_key = env["entries"].to_h { |e| [e["key"], e] }

    expect(by_key["identity.self"]["derived"]).to be false
    expect(by_key["identity.self"]["intake"]).to be false

    expect(by_key["intake.feed"]["intake"]).to be true
    expect(by_key["intake.feed"]["derived"]).to be false

    expect(by_key["output.report"]["derived"]).to be true
    expect(by_key["output.report"]["publish_to"]).to eq(["REPORT.md"])
    expect(by_key["output.report"]["publish_each"]).to be_nil

    expect(by_key["working.notes"]["nested"]).to be true
  end

  it "lists hooks grouped by event, sorted alphabetically" do
    env = described_class.build(container: store.container)
    ext = env["hooks"]
    expect(ext["transform_rows"]).to eq(%w[alpha rank_by_recency])
    # demo-action, apple, zebra + builtins (json, csv, markdown-links, ical-events, rss)
    expect(ext["resolve_intake"]).to include("apple", "demo-action", "zebra")
    expect(ext["resolve_intake"]).to eq(ext["resolve_intake"].sort)
    expect(ext["build_completed"]).to eq(["stamp_log"])
    expect(ext["validate"]).to include("smoke")
  end

  it "includes verbatim write_flows and cli_verbs" do
    env = described_class.build(container: store.container)
    expect(env["write_flows"]).to include("human", "agent", "automation")
    expect(env["write_flows"]["agent"]).to include("proposal:")

    # human holds [accept, propose] → its write_flow joins both guidance
    # strings (accept's 'textus put' + propose's 'proposal:') with ' / '.
    expect(env["write_flows"]["human"]).to include("textus put").and include(" / ").and include("proposal:")

    names = env["cli_verbs"].map { |v| v["name"] }
    expect(names).to include("boot", "list", "get", "put", "accept", "build", "doctor", "hook")
  end

  describe "agent_protocol block" do
    it "includes envelope_shape, role_resolution, and recipes" do
      result = Textus::Boot.build(container: store.container)
      expect(result).to have_key("agent_protocol")
      block = result["agent_protocol"]
      expect(block).to have_key("envelope_shape")
      expect(block).to have_key("role_resolution")
      expect(block["recipes"].keys).to contain_exactly("read", "write", "propose", "fetch")
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
      expect(result["zones"]).to be_a(Array)
      expect(result["entries"]).to be_a(Array)
      expect(result["hooks"]).to be_a(Hash)
      expect(result["write_flows"]).to be_a(Hash)
      expect(result["cli_verbs"]).to be_a(Array)
      expect(result["docs"]).to be_a(Hash)
    end
  end

  describe "with user-renamed roles" do
    def build_store(yaml)
      dir = Dir.mktmpdir("textus-boot-renamed-")
      FileUtils.mkdir_p(File.join(dir, "schemas"))
      File.write(File.join(dir, "manifest.yaml"), yaml)
      Textus::Store.new(dir)
    end

    it "renders write_flows keyed by the configured role names" do
      yaml = <<~YAML
        version: textus/3
        roles:
          - { name: owner,    can: [accept] }
          - { name: proposer, can: [propose] }
          - { name: fetcher,  can: [fetch] }
          - { name: compiler, can: [build] }
        zones:
          - { name: self,    kind: origin }
          - { name: review,  kind: queue }
          - { name: world,   kind: quarantine }
          - { name: build,   kind: derived }
        entries: []
      YAML
      s = build_store(yaml)
      env = described_class.build(container: s.container)
      flows = env["write_flows"]
      expect(flows.keys).to contain_exactly("owner", "proposer", "fetcher", "compiler")
      expect(flows["owner"]).to include("owner")
      expect(flows["proposer"]).to include("proposer", "owner")
      expect(flows["proposer"]).not_to include("accept_authority")
      expect(flows["fetcher"]).to include("fetcher")

      roles = env["agent_protocol"]["role_resolution"]["roles"]
      expect(roles).to eq(%w[owner proposer fetcher compiler])
    end

    it "falls back to default role names when roles: block is omitted" do
      yaml = <<~YAML
        version: textus/3
        zones:
          - { name: identity, kind: origin }
          - { name: review,   kind: queue }
          - { name: output,   kind: derived }
        entries: []
      YAML
      s = build_store(yaml)
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
    code = Textus::CLI.run(["boot", "--output=json"],
                           stdin: StringIO.new(""), stdout: out, stderr: err, cwd: tmp)
    expect(code).to eq(0)
    parsed = JSON.parse(out.string)
    expect(parsed["protocol"]).to eq("textus/3")
    expect(parsed["zones"].length).to eq(5)
    expect(parsed["cli_verbs"]).to be_an(Array)
  end
end
