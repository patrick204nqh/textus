require "spec_helper"
require "tmpdir"
require "fileutils"
require "json"
require "stringio"

RSpec.describe Textus::Intro do
  let(:tmp)  { Dir.mktmpdir }
  let(:root) { File.join(tmp, ".textus") }

  before do
    FileUtils.mkdir_p(File.join(root, "zones/canon"))
    FileUtils.mkdir_p(File.join(root, "zones/working/notes"))
    FileUtils.mkdir_p(File.join(root, "zones/intake"))
    FileUtils.mkdir_p(File.join(root, "zones/derived"))
    FileUtils.mkdir_p(File.join(root, "zones/pending"))
    FileUtils.mkdir_p(File.join(root, "schemas"))
    FileUtils.mkdir_p(File.join(root, "templates"))
    FileUtils.mkdir_p(File.join(root, "extensions"))

    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/2
      zones:
        - { name: canon,   writable_by: [human] }
        - { name: working, writable_by: [human, ai, script] }
        - { name: intake,  writable_by: [script] }
        - { name: pending, writable_by: [ai] }
        - { name: derived, writable_by: [build] }
      entries:
        - { key: canon.identity, path: canon/identity.md, zone: canon, schema: null, owner: human:self }
        - key: working.notes
          path: working/notes
          zone: working
          schema: null
          nested: true
        - key: intake.feed
          path: intake/feed.md
          zone: intake
          owner: script:local
          source:
            action: demo-action
            config: { foo: 1 }
            ttl: 6h
        - key: derived.report
          path: derived/report.md
          zone: derived
          owner: build:auto
          projection:
            select: [working.notes]
            pluck: "*"
          template: report.mustache
          publish_to: [REPORT.md]
    YAML

    File.write(File.join(root, "templates/report.mustache"), "ok\n")

    File.write(File.join(root, "extensions/exts.rb"), <<~RUBY)
      Textus.action(:demo_action)  { |config:, store:, args:| { frontmatter: {}, body: "" } }
      Textus.action(:zebra)        { |config:, store:, args:| { frontmatter: {}, body: "" } }
      Textus.action(:apple)        { |config:, store:, args:| { frontmatter: {}, body: "" } }
      Textus.reducer(:rank_by_recency) { |rows:, config:| rows }
      Textus.reducer(:alpha)           { |rows:, config:| rows }
      Textus.hook(:build, :stamp_log)  { |**_| }
      Textus.doctor_check(:smoke)      { |store:| { ok: true } }
    RUBY
  end

  after { FileUtils.remove_entry(tmp) }

  def store
    @store ||= Textus::Store.new(root)
  end

  it "returns an envelope with protocol + store_root" do
    env = described_class.run(store)
    expect(env["protocol"]).to eq("textus/2")
    expect(env["store_root"]).to eq(root)
  end

  it "lists zones with writers and purposes for known zones" do
    env = described_class.run(store)
    names = env["zones"].map { |z| z["name"] }
    expect(names).to contain_exactly("canon", "working", "intake", "pending", "derived")
    canon = env["zones"].find { |z| z["name"] == "canon" }
    expect(canon["writers"]).to eq(["human"])
    expect(canon["purpose"]).to include("human-only")

    working = env["zones"].find { |z| z["name"] == "working" }
    expect(working["writers"]).to include("human", "ai", "script")
    expect(working).to have_key("purpose")
  end

  it "omits purpose for unknown zone names" do
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/2
      zones:
        - { name: canon, writable_by: [human] }
        - { name: weird, writable_by: [human] }
      entries:
        - { key: canon.identity, path: canon/identity.md, zone: canon, schema: null }
    YAML
    s = Textus::Store.new(root)
    env = described_class.run(s)
    weird = env["zones"].find { |z| z["name"] == "weird" }
    expect(weird).not_to have_key("purpose")
  end

  it "lists entries with derived, intake, publish_to flags" do
    env = described_class.run(store)
    by_key = env["entries"].to_h { |e| [e["key"], e] }

    expect(by_key["canon.identity"]["derived"]).to be false
    expect(by_key["canon.identity"]["intake"]).to be false

    expect(by_key["intake.feed"]["intake"]).to be true
    expect(by_key["intake.feed"]["derived"]).to be false

    expect(by_key["derived.report"]["derived"]).to be true
    expect(by_key["derived.report"]["publish_to"]).to eq(["REPORT.md"])
    expect(by_key["derived.report"]["publish_each"]).to be_nil

    expect(by_key["working.notes"]["nested"]).to be true
  end

  it "lists extensions sorted alphabetically" do
    env = described_class.run(store)
    ext = env["extensions"]
    expect(ext["reducers"]).to eq(%w[alpha rank_by_recency])
    # demo_action, apple, zebra + builtins (json, csv, markdown-links, ical-events, rss)
    expect(ext["actions"]).to include("apple", "demo_action", "zebra")
    expect(ext["actions"]).to eq(ext["actions"].sort)
    expect(ext["hooks"]).to eq([{ "event" => "build", "name" => "stamp_log" }])
    expect(ext["doctor_checks"]).to include("smoke")
  end

  it "includes verbatim write_flows and cli_verbs" do
    env = described_class.run(store)
    expect(env["write_flows"]).to include("human", "ai", "script", "build")
    expect(env["write_flows"]["ai"]).to include("proposal:")

    names = env["cli_verbs"].map { |v| v["name"] }
    expect(names).to include("intro", "list", "get", "put", "accept", "build", "doctor", "extensions")
  end

  it "is callable through the CLI as JSON" do
    out = StringIO.new
    err = StringIO.new
    code = Textus::CLI.run(["intro", "--format=json"],
                           stdin: StringIO.new(""), stdout: out, stderr: err, cwd: tmp)
    expect(code).to eq(0)
    parsed = JSON.parse(out.string)
    expect(parsed["protocol"]).to eq("textus/2")
    expect(parsed["zones"].length).to eq(5)
    expect(parsed["cli_verbs"]).to be_an(Array)
  end
end
