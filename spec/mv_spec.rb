require "spec_helper"
require "fileutils"
require "tmpdir"
require "json"

RSpec.describe "textus mv" do
  let(:tmp) { Dir.mktmpdir }
  let(:store) { Textus::Store.new(root) }
  let(:root) { File.join(tmp, ".textus") }

  before do
    FileUtils.mkdir_p(File.join(root, "zones/working/notes"))
    FileUtils.mkdir_p(File.join(root, "zones/canon/notes"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/1
      zones:
        - { name: working, writable_by: [human, ai, script] }
        - { name: canon,   writable_by: [human] }
      entries:
        - { key: working.notes, path: working/notes, zone: working, nested: true }
        - { key: canon.notes,   path: canon/notes,   zone: canon,   nested: true }
    YAML
  end

  after { FileUtils.remove_entry(tmp) }

  def put_md(key, body: "hi")
    basename = key.split(".").last
    store.put(key, frontmatter: { "name" => basename }, body: body, as: "human")
  end

  it "moves an entry within the same zone, preserving uid" do
    env = put_md("working.notes.alpha")
    uid = env["uid"]
    res = store.mv("working.notes.alpha", "working.notes.beta", as: "human")
    expect(res["ok"]).to be true
    expect(res["uid"]).to eq(uid)
    expect(File.exist?(File.join(root, "zones/working/notes/alpha.md"))).to be false
    expect(File.exist?(File.join(root, "zones/working/notes/beta.md"))).to be true
    expect(store.get("working.notes.beta")["uid"]).to eq(uid)
  end

  it "writes an audit row with verb=mv and top-level structural fields" do
    put_md("working.notes.alpha")
    store.mv("working.notes.alpha", "working.notes.beta", as: "human")
    line = File.read(File.join(root, "audit.log")).lines.last.chomp
    parsed = JSON.parse(line)
    expect(parsed["verb"]).to eq("mv")
    expect(parsed["key"]).to eq("working.notes.beta")
    expect(parsed["from_key"]).to eq("working.notes.alpha")
    expect(parsed["to_key"]).to eq("working.notes.beta")
    expect(parsed["uid"]).to match(/\A[a-f0-9]{12,}\z/)
    expect(parsed["extras"]["from_path"]).to end_with("working/notes/alpha.md")
    expect(parsed["extras"]["to_path"]).to end_with("working/notes/beta.md")
  end

  it "refuses cross-zone moves" do
    put_md("working.notes.alpha")
    expect do
      store.mv("working.notes.alpha", "canon.notes.alpha", as: "human")
    end.to raise_error(Textus::UsageError, /cross-zone/)
  end

  it "refuses to clobber an existing target" do
    put_md("working.notes.alpha")
    put_md("working.notes.beta")
    expect do
      store.mv("working.notes.alpha", "working.notes.beta", as: "human")
    end.to raise_error(Textus::UsageError, /already exists/)
  end

  it "refuses when the new key fails grammar" do
    put_md("working.notes.alpha")
    expect do
      store.mv("working.notes.alpha", "working.notes.Bad_Name", as: "human")
    end.to raise_error(Textus::UsageError, /invalid key segment/)
  end

  it "--dry-run does not move and reports the plan" do
    put_md("working.notes.alpha")
    res = store.mv("working.notes.alpha", "working.notes.beta", as: "human", dry_run: true)
    expect(res["dry_run"]).to be true
    expect(File.exist?(File.join(root, "zones/working/notes/alpha.md"))).to be true
    expect(File.exist?(File.join(root, "zones/working/notes/beta.md"))).to be false
  end

  it "mints a uid if the source had none, so the audit row carries it" do
    src = File.join(root, "zones/working/notes/alpha.md")
    File.write(src, "---\nname: alpha\n---\nbody\n")
    expect(store.get("working.notes.alpha")["uid"]).to be_nil

    res = store.mv("working.notes.alpha", "working.notes.beta", as: "human")
    expect(res["uid"]).to match(/\A[a-f0-9]{12,}\z/)
    expect(store.get("working.notes.beta")["uid"]).to eq(res["uid"])

    line = File.read(File.join(root, "audit.log")).lines.last
    parsed = JSON.parse(line.chomp)
    expect(parsed["uid"]).to eq(res["uid"])
  end

  it "is wired up in the CLI" do
    put_md("working.notes.alpha")
    out = StringIO.new
    err = StringIO.new
    code = Textus::CLI.run(
      ["mv", "working.notes.alpha", "working.notes.beta", "--as=human", "--format=json"],
      stdin: StringIO.new, stdout: out, stderr: err, cwd: File.dirname(root),
    )
    expect(code).to eq(0), "stdout=#{out.string} stderr=#{err.string}"
    payload = JSON.parse(out.string.lines.last)
    expect(payload["ok"]).to be true
    expect(payload["to_key"]).to eq("working.notes.beta")
  end
end
