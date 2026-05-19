require "spec_helper"
require "fileutils"
require "tmpdir"
require "json"
require "stringio"

RSpec.describe "CLI extension verbs" do
  let(:tmp)  { Dir.mktmpdir }
  let(:root) { File.join(tmp, ".textus") }

  before do
    FileUtils.mkdir_p(File.join(root, "zones/intake"))
    FileUtils.mkdir_p(File.join(root, "extensions"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/1
      zones: [{ name: intake, writable_by: [script] }]
      entries:
        - key: intake.x
          path: intake/x.md
          zone: intake
          source: { fetcher: stub }
    YAML
    File.write(File.join(root, "extensions/ext.rb"), <<~RUBY)
      Textus.fetcher(:stub) { |config:, store:| { frontmatter: { "name" => "x" }, body: "ok" } }
      Textus.reducer(:r)     { |rows:, config:| rows }
      Textus.hook(:put, :h)  { |key:, envelope:, store:| }
    RUBY
  end

  after { FileUtils.remove_entry(tmp) }

  def run_cli(argv)
    out = StringIO.new
    rc = Textus::CLI.run(argv, stdin: StringIO.new, stdout: out, stderr: StringIO.new, cwd: tmp)
    [rc, out.string.lines.last]
  end

  it "textus refresh KEY invokes the fetcher" do
    rc, line = run_cli(["refresh", "intake.x", "--as=script", "--format=json"])
    expect(rc).to eq(0)
    expect(JSON.parse(line)["body"]).to eq("ok")
  end

  it "textus extensions list returns fetcher/reducer/hook names" do
    rc, line = run_cli(["extensions", "list", "--format=json"])
    expect(rc).to eq(0)
    payload = JSON.parse(line)
    names = payload["extensions"].group_by { |e| e["kind"] }
    expect(names["fetcher"].map { |e| e["name"] }).to include("stub")
    expect(names["reducer"].map { |e| e["name"] }).to include("r")
    expect(names["hook"].map { |e| e["name"] }).to include("h")
  end

  it "textus extensions list --kind=hook filters" do
    _rc, line = run_cli(["extensions", "list", "--kind=hook", "--format=json"])
    expect(JSON.parse(line)["extensions"].map { |e| e["kind"] }).to all(eq("hook"))
  end

  it "textus put --fetcher=NAME applies the fetcher to stdin bytes" do
    FileUtils.mkdir_p(File.join(root, "zones/working"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/1
      zones: [{ name: working, writable_by: [human, script] }]
      entries: [{ key: working.j, path: working/j.md, zone: working }]
    YAML
    out = StringIO.new
    rc = Textus::CLI.run(
      ["put", "working.j", "--stdin", "--fetcher=json", "--as=human", "--format=json"],
      stdin: StringIO.new('{"a":1}'), stdout: out, stderr: StringIO.new, cwd: tmp,
    )
    expect(rc).to eq(0)
  end

  it "removed: textus hooks list exits with usage error" do
    rc, line = run_cli(["hooks", "list", "--format=json"])
    expect(rc).not_to eq(0)
    expect(JSON.parse(line)["code"]).to eq("usage")
  end
end
