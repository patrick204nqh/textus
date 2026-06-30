require "spec_helper"

RSpec.describe "Textus UID" do
  include_context "textus_store_fixture"

  let(:store) { Textus::Store.new(root) }

  before do
    FileUtils.mkdir_p(File.join(root, "data/knowledge"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/4
      lanes:
        - { name: knowledge, kind: canon }
      entries:
        - { key: knowledge.md,   path: knowledge/md.md,   lane: knowledge, kind: leaf}

        - { key: knowledge.j,    path: knowledge/j.json,  lane: knowledge, kind: leaf}

        - { key: knowledge.y,    path: knowledge/y.yaml,  lane: knowledge, kind: leaf}

        - { key: knowledge.t,    path: knowledge/t.txt,   lane: knowledge, kind: leaf}

    YAML
  end

  it "auto-mints a uid on first put for markdown" do
    env = store.with_role("human").entry(:put, "knowledge.md", meta: { "name" => "md" }, body: "hi")
    expect(env.uid).to match(/\A[a-f0-9]{12,}\z/)
  end

  it "preserves the uid on subsequent puts" do
    ops = store.with_role("human")
    e1 = ops.entry(:put, "knowledge.md", meta: { "name" => "md" }, body: "hi")
    uid = e1.uid
    e2 = ops.entry(:put, "knowledge.md", meta: { "name" => "md" }, body: "again")
    expect(e2.uid).to eq(uid)
    e3 = store.with_role(Textus::Value::Role::DEFAULT).entry(:get, "knowledge.md")
    expect(e3.uid).to eq(uid)
  end

  it "shows nil uid for existing files that have none, then mints on put" do
    path = File.join(root, "data/knowledge/md.md")
    File.write(path, "---\nname: md\n---\nhand-rolled\n")
    expect(store.with_role(Textus::Value::Role::DEFAULT).entry(:get, "knowledge.md").uid).to be_nil

    existing = store.with_role(Textus::Value::Role::DEFAULT).entry(:get, "knowledge.md")
    env = store.with_role("human").entry(:put,
                                         "knowledge.md",
                                         meta: existing.meta,
                                         body: existing.body)
    expect(env.uid).to match(/\A[a-f0-9]{16}\z/)
  end

  it "stores uid in _meta.entry(:uid) for json entries (accessible via env['_meta'])" do
    env = store.with_role("human").entry(:put, "knowledge.j", content: { "name" => "j", "x" => 1 })
    expect(env.uid).to match(/\A[a-f0-9]{12,}\z/)
    expect(env.meta["uid"]).to eq(env.uid)
  end

  it "stores uid in _meta.entry(:uid) for yaml entries (accessible via env['_meta'])" do
    env = store.with_role("human").entry(:put, "knowledge.y", content: { "name" => "y", "x" => 1 })
    expect(env.uid).to match(/\A[a-f0-9]{12,}\z/)
    expect(env.meta["uid"]).to eq(env.uid)
  end

  it "yields nil uid for text entries even after put" do
    env = store.with_role("human").entry(:put, "knowledge.t", body: "plain text")
    expect(env.uid).to be_nil
  end

  it "Store#uid returns the uid for a key" do
    env = store.with_role("human").entry(:put, "knowledge.md", meta: { "name" => "md" }, body: "hi")
    expect(store.with_role(Textus::Value::Role::DEFAULT).entry(:uid, "knowledge.md")).to eq(env.uid)
  end
end
