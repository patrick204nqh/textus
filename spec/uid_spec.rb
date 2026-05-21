require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe "Textus UID" do
  let(:tmp) { Dir.mktmpdir }
  let(:store) { Textus::Store.new(root) }
  let(:root) { File.join(tmp, ".textus") }

  before do
    FileUtils.mkdir_p(File.join(root, "zones/working"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/2
      zones:
        - { name: working, writable_by: [human, ai, script] }
      entries:
        - { key: working.md,   path: working/md.md,   zone: working }
        - { key: working.j,    path: working/j.json,  zone: working }
        - { key: working.y,    path: working/y.yaml,  zone: working }
        - { key: working.t,    path: working/t.txt,   zone: working }
    YAML
  end

  after { FileUtils.remove_entry(tmp) }

  it "auto-mints a uid on first put for markdown" do
    env = store.put("working.md", meta: { "name" => "md" }, body: "hi", as: "human")
    expect(env["uid"]).to match(/\A[a-f0-9]{12,}\z/)
  end

  it "preserves the uid on subsequent puts" do
    e1 = store.put("working.md", meta: { "name" => "md" }, body: "hi", as: "human")
    uid = e1["uid"]
    e2 = store.put("working.md", meta: { "name" => "md" }, body: "again", as: "human")
    expect(e2["uid"]).to eq(uid)
    e3 = store.get("working.md")
    expect(e3["uid"]).to eq(uid)
  end

  it "shows nil uid for existing files that have none, then mints on put" do
    path = File.join(root, "zones/working/md.md")
    File.write(path, "---\nname: md\n---\nhand-rolled\n")
    expect(store.get("working.md")["uid"]).to be_nil

    env = store.put("working.md", meta: store.get("working.md")["_meta"],
                                  body: store.get("working.md")["body"], as: "human")
    expect(env["uid"]).to match(/\A[a-f0-9]{16}\z/)
  end

  it "stores uid in _meta.uid for json entries (accessible via env['_meta'])" do
    env = store.put("working.j", content: { "name" => "j", "x" => 1 }, as: "human")
    expect(env["uid"]).to match(/\A[a-f0-9]{12,}\z/)
    expect(env["_meta"]["uid"]).to eq(env["uid"])
  end

  it "stores uid in _meta.uid for yaml entries (accessible via env['_meta'])" do
    env = store.put("working.y", content: { "name" => "y", "x" => 1 }, as: "human")
    expect(env["uid"]).to match(/\A[a-f0-9]{12,}\z/)
    expect(env["_meta"]["uid"]).to eq(env["uid"])
  end

  it "yields nil uid for text entries even after put" do
    env = store.put("working.t", body: "plain text", as: "human")
    expect(env["uid"]).to be_nil
  end

  it "Store#uid returns the uid for a key" do
    env = store.put("working.md", meta: { "name" => "md" }, body: "hi", as: "human")
    expect(store.uid("working.md")).to eq(env["uid"])
  end
end
