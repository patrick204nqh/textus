require "spec_helper"

# The `key delete` overload split into two first-class generated commands
# (ADR 0068): `key delete KEY` dispatches :delete, `key delete-prefix PREFIX`
# dispatches :key_delete_prefix. BREAKING: `key delete --prefix P` is gone.
RSpec.describe "textus key group (delete / delete-prefix split, ADR 0068)" do
  include_context "textus_store_fixture"
  include_context "cli invocation"

  before do
    FileUtils.mkdir_p(File.join(root, "data/working/notes"))
    FileUtils.mkdir_p(File.join(root, "data/working/archive"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/4
      lanes:
        - { name: working, kind: canon }
      entries:
        - { key: working.notes, path: working/notes, lane: working, owner: human:self, kind: nested, nested: true }
        - { key: working.archive, path: working/archive, lane: working, owner: human:self, kind: nested, nested: true }
    YAML
    File.write(File.join(root, "data/working/notes/a.md"), "---\n_meta: {name: a, uid: aaaaaaaaaaaaaaaa}\n---\nA\n")
    File.write(File.join(root, "data/working/notes/b.md"), "---\n_meta: {name: b, uid: bbbbbbbbbbbbbbbb}\n---\nB\n")
    FileUtils.mkdir_p(audit_dir_path(root))
    File.write(audit_log_path(root), "")
  end

  it "`key delete KEY` dispatches :delete and removes the single entry" do
    rc = run(["--root=#{root}", "key", "delete", "working.notes.a", "--as=human"])
    expect(rc).to eq(0), "stderr: #{stderr.string}"
    payload = JSON.parse(stdout.string)
    expect(payload).to include("ok" => true, "key" => "working.notes.a", "deleted" => true)
    expect(File.exist?(File.join(root, "data/working/notes/a.md"))).to be(false)
    expect(File.exist?(File.join(root, "data/working/notes/b.md"))).to be(true)
  end

  it "`key delete-prefix PREFIX` dispatches :key_delete_prefix and APPLIES by default" do
    rc = run(["--root=#{root}", "key", "delete-prefix", "working.notes", "--as=human"])
    expect(rc).to eq(0), "stderr: #{stderr.string}"
    payload = JSON.parse(stdout.string)
    expect(payload["steps"].map { |s| s["op"] }).to all(eq("delete"))
    expect(File.exist?(File.join(root, "data/working/notes/a.md"))).to be(false)
    expect(File.exist?(File.join(root, "data/working/notes/b.md"))).to be(false)
  end

  it "`key delete-prefix PREFIX --dry-run` plans without deleting" do
    rc = run(["--root=#{root}", "key", "delete-prefix", "working.notes", "--as=human", "--dry-run"])
    expect(rc).to eq(0), "stderr: #{stderr.string}"
    expect(File.exist?(File.join(root, "data/working/notes/a.md"))).to be(true)
  end

  it "`key mv OLD NEW` dispatches :mv and applies by default" do
    rc = run(["--root=#{root}", "key", "mv", "working.notes.a", "working.notes.c", "--as=human"])
    expect(rc).to eq(0), "stderr: #{stderr.string}"
    payload = JSON.parse(stdout.string)
    expect(payload).to include("ok" => true, "from_key" => "working.notes.a", "to_key" => "working.notes.c")
    expect(File.exist?(File.join(root, "data/working/notes/a.md"))).to be(false)
    expect(File.exist?(File.join(root, "data/working/notes/c.md"))).to be(true)
  end

  it "`key mv-prefix FROM TO` dispatches :key_mv_prefix and APPLIES by default" do
    rc = run(["--root=#{root}", "key", "mv-prefix", "working.notes", "working.archive", "--as=human"])
    expect(rc).to eq(0), "stderr: #{stderr.string}"
    payload = JSON.parse(stdout.string)
    expect(payload["steps"].map { |s| s["op"] }).to all(eq("mv"))
    expect(File.exist?(File.join(root, "data/working/archive/a.md"))).to be(true)
  end
end
