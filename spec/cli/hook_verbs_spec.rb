require "spec_helper"
require "stringio"

RSpec.describe "CLI hook verbs" do
  include_context "textus_store_fixture"

  before do
    FileUtils.mkdir_p(File.join(root, "zones/intake"))
    FileUtils.mkdir_p(File.join(root, "hooks"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones: [{ name: intake, kind: quarantine }]
      entries:
        - key: intake.x
          kind: intake
          path: intake/x.md
          zone: intake
          intake: { handler: stub }
    YAML
    File.write(File.join(root, "hooks/ext.rb"), <<~RUBY)
      Textus.hook do |reg|
        reg.on(:resolve_intake, :stub) { |caps:, config:, args:| { _meta: { "name" => "x" }, body: "ok" } }
        reg.on(:transform_rows, :r)    { |caps:, rows:, config:| rows }
        reg.on(:entry_put, :h)         { |**| }
        reg.on(:validate, :dc)         { |caps:| [] }
      end
    RUBY
  end

  def run_cli(argv)
    out = StringIO.new
    rc = Textus::CLI.run(argv, stdin: StringIO.new, stdout: out, stderr: StringIO.new, cwd: tmp)
    [rc, out.string.lines.last]
  end

  it "textus fetch KEY invokes the fetch hook" do
    rc, line = run_cli(["fetch", "intake.x", "--as=automation", "--output=json"])
    expect(rc).to eq(0)
    expect(JSON.parse(line)["body"]).to eq("ok")
  end

  it "textus hook list returns hooks grouped by event" do
    rc, line = run_cli(["hook", "list", "--output=json"])
    expect(rc).to eq(0)
    payload = JSON.parse(line)
    by_event = payload["hooks"].group_by { |e| e["event"] }
    expect(by_event["resolve_intake"].map { |e| e["name"] }).to include("stub")
    expect(by_event["transform_rows"].map { |e| e["name"] }).to include("r")
    expect(by_event["entry_put"].map { |e| e["name"] }).to include("h")
    expect(by_event["validate"].map { |e| e["name"] }).to include("dc")
  end

  it "textus hook list --event=entry_put filters" do
    _rc, line = run_cli(["hook", "list", "--event=entry_put", "--output=json"])
    expect(JSON.parse(line)["hooks"].map { |e| e["event"] }).to all(eq("entry_put"))
  end

  it "textus put --fetch=NAME applies the fetch hook to stdin bytes" do
    FileUtils.mkdir_p(File.join(root, "zones/working"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones: [{ name: working, kind: canon }]
      entries: [{ key: working.j, path: working/j.md, zone: working, kind: leaf }]
    YAML
    File.write(File.join(root, "hooks/jfetch.rb"), <<~RUBY)
      Textus.hook do |reg|
        reg.on(:resolve_intake, :jbytes) { |caps:, config:, args:| { _meta: {}, body: config["bytes"] } }
      end
    RUBY
    out = StringIO.new
    rc = Textus::CLI.run(
      ["put", "working.j", "--stdin", "--fetch=jbytes", "--as=human", "--output=json"],
      stdin: StringIO.new('{"a":1}'), stdout: out, stderr: StringIO.new, cwd: tmp,
    )
    expect(rc).to eq(0)
  end

  it "removed: textus extensions list exits with usage error" do
    rc, line = run_cli(["extensions", "list", "--output=json"])
    expect(rc).not_to eq(0)
    expect(JSON.parse(line)["code"]).to eq("usage")
  end
end
