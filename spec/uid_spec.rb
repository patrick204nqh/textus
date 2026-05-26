require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe "Textus UID" do
  include_context "textus_store_fixture"

  let(:store) { Textus::Store.new(root) }

  before do
    FileUtils.mkdir_p(File.join(root, "zones/working"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: working, write_policy: [human, agent, runner] }
      entries:
        - { key: working.md,   path: working/md.md,   zone: working }
        - { key: working.j,    path: working/j.json,  zone: working }
        - { key: working.y,    path: working/y.yaml,  zone: working }
        - { key: working.t,    path: working/t.txt,   zone: working }
    YAML
  end

  it "auto-mints a uid on first put for markdown" do
    env = Textus::Operations.for(store, role: "human").put("working.md", meta: { "name" => "md" }, body: "hi")
    expect(env.uid).to match(/\A[a-f0-9]{12,}\z/)
  end

  it "preserves the uid on subsequent puts" do
    ops = Textus::Operations.for(store, role: "human")
    e1 = ops.put("working.md", meta: { "name" => "md" }, body: "hi")
    uid = e1.uid
    e2 = ops.put("working.md", meta: { "name" => "md" }, body: "again")
    expect(e2.uid).to eq(uid)
    e3 = store.reader.get("working.md")
    expect(e3.uid).to eq(uid)
  end

  it "shows nil uid for existing files that have none, then mints on put" do
    path = File.join(root, "zones/working/md.md")
    File.write(path, "---\nname: md\n---\nhand-rolled\n")
    expect(store.reader.get("working.md").uid).to be_nil

    existing = store.reader.get("working.md")
    env = Textus::Operations.for(store, role: "human").put(
      "working.md",
      meta: existing.meta,
      body: existing.body,
    )
    expect(env.uid).to match(/\A[a-f0-9]{16}\z/)
  end

  it "stores uid in _meta.uid for json entries (accessible via env['_meta'])" do
    env = Textus::Operations.for(store, role: "human").put("working.j", content: { "name" => "j", "x" => 1 })
    expect(env.uid).to match(/\A[a-f0-9]{12,}\z/)
    expect(env.meta["uid"]).to eq(env.uid)
  end

  it "stores uid in _meta.uid for yaml entries (accessible via env['_meta'])" do
    env = Textus::Operations.for(store, role: "human").put("working.y", content: { "name" => "y", "x" => 1 })
    expect(env.uid).to match(/\A[a-f0-9]{12,}\z/)
    expect(env.meta["uid"]).to eq(env.uid)
  end

  it "yields nil uid for text entries even after put" do
    env = Textus::Operations.for(store, role: "human").put("working.t", body: "plain text")
    expect(env.uid).to be_nil
  end

  it "Store#uid returns the uid for a key" do
    env = Textus::Operations.for(store, role: "human").put("working.md", meta: { "name" => "md" }, body: "hi")
    expect(Textus::Operations.for(store).uid("working.md")).to eq(env.uid)
  end
end
