require "spec_helper"
require "tmpdir"
require "fileutils"
require "json"
require "stringio"

RSpec.describe Textus::Intro do
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
      zones:
        - { name: identity, write_policy: [human] }
        - { name: working,  write_policy: [human, agent, runner] }
        - { name: intake,   write_policy: [runner] }
        - { name: review,   write_policy: [agent] }
        - { name: output,   write_policy: [builder] }
      entries:
        - { key: identity.self, path: identity/self.md, zone: identity, schema: null, owner: human:self }
        - key: working.notes
          path: working/notes
          zone: working
          schema: null
          nested: true
        - key: intake.feed
          path: intake/feed.md
          zone: intake
          owner: runner:local
          intake:
            handler: demo-action
            config: { foo: 1 }
        - key: output.report
          path: output/report.md
          zone: output
          owner: builder:auto
          compute:
            kind: projection
            select: [working.notes]
            pluck: "*"
          template: report.mustache
          publish_to: [REPORT.md]
    YAML

    File.write(File.join(root, "templates/report.mustache"), "ok\n")

    File.write(File.join(root, "hooks/exts.rb"), <<~RUBY)
      Textus.on(:resolve_intake, :"demo-action") { |store:, config:, args:| { _meta: {}, body: "" } }
      Textus.on(:resolve_intake, :zebra)         { |store:, config:, args:| { _meta: {}, body: "" } }
      Textus.on(:resolve_intake, :apple)         { |store:, config:, args:| { _meta: {}, body: "" } }
      Textus.on(:transform_rows, :rank_by_recency) { |store:, rows:, config:| rows }
      Textus.on(:transform_rows, :alpha)           { |store:, rows:, config:| rows }
      Textus.on(:build_completed, :stamp_log)        { |store:, key:, envelope:, sources:| }
      Textus.on(:validate, :smoke)            { |store:| [] }
    RUBY
  end

  def store
    @store ||= Textus::Store.new(root)
  end

  it "returns an envelope with protocol + store_root" do
    env = described_class.run(store)
    expect(env["protocol"]).to eq("textus/3")
    expect(env["store_root"]).to eq(root)
  end

  it "lists zones with writers and purposes for known zones" do
    env = described_class.run(store)
    names = env["zones"].map { |z| z["name"] }
    expect(names).to contain_exactly("identity", "working", "intake", "review", "output")
    identity = env["zones"].find { |z| z["name"] == "identity" }
    expect(identity["writers"]).to eq(["human"])
    expect(identity["purpose"]).to include("human-only")

    working = env["zones"].find { |z| z["name"] == "working" }
    expect(working["writers"]).to include("human", "agent", "runner")
    expect(working).to have_key("purpose")
  end

  it "omits purpose for unknown zone names" do
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: identity, write_policy: [human] }
        - { name: weird,    write_policy: [human] }
      entries:
        - { key: identity.self, path: identity/self.md, zone: identity, schema: null }
    YAML
    s = Textus::Store.new(root)
    env = described_class.run(s)
    weird = env["zones"].find { |z| z["name"] == "weird" }
    expect(weird).not_to have_key("purpose")
  end

  it "lists entries with derived, intake, publish_to flags" do
    env = described_class.run(store)
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
    env = described_class.run(store)
    ext = env["hooks"]
    expect(ext["transform_rows"]).to eq(%w[alpha rank_by_recency])
    # demo-action, apple, zebra + builtins (json, csv, markdown-links, ical-events, rss)
    expect(ext["resolve_intake"]).to include("apple", "demo-action", "zebra")
    expect(ext["resolve_intake"]).to eq(ext["resolve_intake"].sort)
    expect(ext["build_completed"]).to eq(["stamp_log"])
    expect(ext["validate"]).to include("smoke")
  end

  it "includes verbatim write_flows and cli_verbs" do
    env = described_class.run(store)
    expect(env["write_flows"]).to include("human", "agent", "runner", "builder")
    expect(env["write_flows"]["agent"]).to include("proposal:")

    names = env["cli_verbs"].map { |v| v["name"] }
    expect(names).to include("intro", "list", "get", "put", "accept", "build", "doctor", "hook")
  end

  describe "agent_protocol block" do
    it "includes envelope_shape, role_resolution, and recipes" do
      result = Textus::Intro.run(store)
      expect(result).to have_key("agent_protocol")
      block = result["agent_protocol"]
      expect(block).to have_key("envelope_shape")
      expect(block).to have_key("role_resolution")
      expect(block["recipes"].keys).to contain_exactly("read", "write", "propose", "refresh")
    end

    it "does not change the wire protocol field" do
      result = Textus::Intro.run(store)
      expect(result["protocol"]).to eq("textus/3")
    end

    it "is omitted from per-recipe output by default (no example field)" do
      result = Textus::Intro.run(store)
      result["agent_protocol"]["recipes"].each_value do |r|
        expect(r).not_to have_key("example")
      end
    end
  end

  describe "agent_protocol with examples" do
    it "includes an example field on every recipe when with_examples: true" do
      result = Textus::Intro.run(store, with_examples: true)
      recipes = result["agent_protocol"]["recipes"]
      %w[read write propose refresh].each do |name|
        expect(recipes[name]).to have_key("example"), "missing example for #{name}"
      end
    end

    it "examples are runnable strings, not nil or empty" do
      result = Textus::Intro.run(store, with_examples: true)
      result["agent_protocol"]["recipes"].each do |name, r|
        ex = r["example"]
        expect(ex).to be_a(Hash), "example for #{name} must be a hash"
        expect(ex["command"]).to match(/\Atextus /), "example.command for #{name} must start with 'textus '"
      end
    end
  end

  describe "backward compatibility" do
    it "keeps every pre-0.12.3 top-level key with its original shape" do
      result = Textus::Intro.run(store)
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

  describe "examples are grounded in examples/claude-plugin" do
    it "every example command references a key that exists in the example store" do
      manifest_path = File.expand_path("../examples/claude-plugin/.textus/manifest.yaml", __dir__)
      skip "example store not present" unless File.exist?(manifest_path)
      manifest = YAML.safe_load_file(manifest_path)
      example_keys = manifest["entries"].map { |e| e["key"] }
      Textus::Intro::EXAMPLES.each do |name, ex|
        cmd = ex["command"]
        key = cmd[/textus \w+ ([a-z0-9.-]+)/, 1]
        next unless key

        match = example_keys.any? { |k| key == k || key.start_with?("#{k}.") }
        expect(match).to be(true), "example '#{name}' references #{key.inspect}, not in #{manifest_path}"
      end
    end
  end

  it "is callable through the CLI as JSON" do
    out = StringIO.new
    err = StringIO.new
    code = Textus::CLI.run(["intro", "--output=json"],
                           stdin: StringIO.new(""), stdout: out, stderr: err, cwd: tmp)
    expect(code).to eq(0)
    parsed = JSON.parse(out.string)
    expect(parsed["protocol"]).to eq("textus/3")
    expect(parsed["zones"].length).to eq(5)
    expect(parsed["cli_verbs"]).to be_an(Array)
  end
end
