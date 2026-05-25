require "spec_helper"
require "fileutils"
require "tmpdir"
require "json"
require "stringio"

RSpec.describe "CLI hook verbs" do
  include_context "textus_store_fixture"

  before do
    FileUtils.mkdir_p(File.join(root, "zones/intake"))
    FileUtils.mkdir_p(File.join(root, "hooks"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones: [{ name: intake, writable_by: [runner] }]
      entries:
        - key: intake.x
          path: intake/x.md
          zone: intake
          intake: { handler: stub }
    YAML
    File.write(File.join(root, "hooks/ext.rb"), <<~RUBY)
      Textus.hook(:intake, :stub) { |store:, config:, args:| { _meta: { "name" => "x" }, body: "ok" } }
      Textus.hook(:reduce, :r)    { |store:, rows:, config:| rows }
      Textus.hook(:put,    :h)    { |store:, key:, envelope:| }
      Textus.hook(:check,  :dc)   { |store:| [] }
    RUBY
  end

  def run_cli(argv)
    out = StringIO.new
    rc = Textus::CLI.run(argv, stdin: StringIO.new, stdout: out, stderr: StringIO.new, cwd: tmp)
    [rc, out.string.lines.last]
  end

  it "textus refresh KEY invokes the fetch hook" do
    rc, line = run_cli(["refresh", "intake.x", "--as=runner", "--format=json"])
    expect(rc).to eq(0)
    expect(JSON.parse(line)["body"]).to eq("ok")
  end

  it "textus hook list returns hooks grouped by event" do
    rc, line = run_cli(["hook", "list", "--format=json"])
    expect(rc).to eq(0)
    payload = JSON.parse(line)
    by_event = payload["hooks"].group_by { |e| e["event"] }
    expect(by_event["intake"].map { |e| e["name"] }).to include("stub")
    expect(by_event["reduce"].map { |e| e["name"] }).to include("r")
    expect(by_event["put"].map { |e| e["name"] }).to include("h")
    expect(by_event["check"].map { |e| e["name"] }).to include("dc")
  end

  it "textus hook list --event=put filters" do
    _rc, line = run_cli(["hook", "list", "--event=put", "--format=json"])
    expect(JSON.parse(line)["hooks"].map { |e| e["event"] }).to all(eq("put"))
  end

  it "textus put --fetch=NAME applies the fetch hook to stdin bytes" do
    FileUtils.mkdir_p(File.join(root, "zones/working"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones: [{ name: working, writable_by: [human, script] }]
      entries: [{ key: working.j, path: working/j.md, zone: working }]
    YAML
    File.write(File.join(root, "hooks/jfetch.rb"), <<~RUBY)
      Textus.hook(:intake, :jbytes) { |store:, config:, args:| { _meta: {}, body: config["bytes"] } }
    RUBY
    out = StringIO.new
    rc = Textus::CLI.run(
      ["put", "working.j", "--stdin", "--fetch=jbytes", "--as=human", "--format=json"],
      stdin: StringIO.new('{"a":1}'), stdout: out, stderr: StringIO.new, cwd: tmp,
    )
    expect(rc).to eq(0)
  end

  it "removed: textus extensions list exits with usage error" do
    rc, line = run_cli(["extensions", "list", "--format=json"])
    expect(rc).not_to eq(0)
    expect(JSON.parse(line)["code"]).to eq("usage")
  end
end
