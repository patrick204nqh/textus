require "spec_helper"
require "fileutils"
require "tmpdir"
require "json"

RSpec.describe "textus mv" do
  include_context "textus_store_fixture"

  let(:store) { Textus::Store.new(root) }

  before do
    FileUtils.mkdir_p(File.join(root, "zones/working/notes"))
    FileUtils.mkdir_p(File.join(root, "zones/identity/notes"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: working, write_policy: [human, agent, runner] }
        - { name: identity,   write_policy: [human] }
      entries:
        - { key: working.notes, path: working/notes, zone: working, nested: true }
        - { key: identity.notes,   path: identity/notes,   zone: identity,   nested: true }
    YAML
  end

  def put_md(key, body: "hi")
    basename = key.split(".").last
    Textus::Operations.for(store, role: "human").writes.put.call(key, meta: { "name" => basename }, body: body)
  end

  it "moves an entry within the same zone, preserving uid" do
    env = put_md("working.notes.alpha")
    uid = env["uid"]
    res = Textus::Operations.for(store, role: "human").writes.mv.call("working.notes.alpha", "working.notes.beta")
    expect(res["ok"]).to be true
    expect(res["uid"]).to eq(uid)
    expect(File.exist?(File.join(root, "zones/working/notes/alpha.md"))).to be false
    expect(File.exist?(File.join(root, "zones/working/notes/beta.md"))).to be true
    expect(store.reader.get("working.notes.beta")["uid"]).to eq(uid)
  end

  it "writes an audit row with verb=mv and top-level structural fields" do
    put_md("working.notes.alpha")
    Textus::Operations.for(store, role: "human").writes.mv.call("working.notes.alpha", "working.notes.beta")
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
      Textus::Operations.for(store, role: "human").writes.mv.call("working.notes.alpha", "identity.notes.alpha")
    end.to raise_error(Textus::UsageError, /cross-zone/)
  end

  it "refuses to clobber an existing target" do
    put_md("working.notes.alpha")
    put_md("working.notes.beta")
    expect do
      Textus::Operations.for(store, role: "human").writes.mv.call("working.notes.alpha", "working.notes.beta")
    end.to raise_error(Textus::UsageError, /already exists/)
  end

  it "refuses when the new key fails grammar" do
    put_md("working.notes.alpha")
    expect do
      Textus::Operations.for(store, role: "human").writes.mv.call("working.notes.alpha", "working.notes.Bad_Name")
    end.to raise_error(Textus::UsageError, /invalid key segment/)
  end

  it "--dry-run does not move and reports the plan" do
    put_md("working.notes.alpha")
    res = Textus::Operations.for(store, role: "human").writes.mv.call("working.notes.alpha", "working.notes.beta", dry_run: true)
    expect(res["dry_run"]).to be true
    expect(File.exist?(File.join(root, "zones/working/notes/alpha.md"))).to be true
    expect(File.exist?(File.join(root, "zones/working/notes/beta.md"))).to be false
  end

  it "mints a uid if the source had none, so the audit row carries it" do
    src = File.join(root, "zones/working/notes/alpha.md")
    File.write(src, "---\nname: alpha\n---\nbody\n")
    expect(store.reader.get("working.notes.alpha")["uid"]).to be_nil

    res = Textus::Operations.for(store, role: "human").writes.mv.call("working.notes.alpha", "working.notes.beta")
    expect(res["uid"]).to match(/\A[a-f0-9]{12,}\z/)
    expect(store.reader.get("working.notes.beta")["uid"]).to eq(res["uid"])

    line = File.read(File.join(root, "audit.log")).lines.last
    parsed = JSON.parse(line.chomp)
    expect(parsed["uid"]).to eq(res["uid"])
  end

  it "is wired up in the CLI" do
    put_md("working.notes.alpha")
    out = StringIO.new
    err = StringIO.new
    code = Textus::CLI.run(
      ["key", "mv", "working.notes.alpha", "working.notes.beta", "--as=human", "--output=json"],
      stdin: StringIO.new, stdout: out, stderr: err, cwd: File.dirname(root),
    )
    expect(code).to eq(0), "stdout=#{out.string} stderr=#{err.string}"
    payload = JSON.parse(out.string.lines.last)
    expect(payload["ok"]).to be true
    expect(payload["to_key"]).to eq("working.notes.beta")
  end
end
