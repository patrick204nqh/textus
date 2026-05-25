require "spec_helper"
require "fileutils"
require "tmpdir"
require "json"
require "yaml"

RSpec.describe Textus::Migration::V3::FrontmatterSweeper do
  let(:tmpdir) { Dir.mktmpdir }
  let(:zones_dir) { File.join(tmpdir, ".textus/zones/intake") }

  before { FileUtils.mkdir_p(zones_dir) }
  after  { FileUtils.rm_rf(tmpdir) }

  def write_file(name, content)
    path = File.join(zones_dir, name)
    File.write(path, content)
    path
  end

  # ── Markdown ────────────────────────────────────────────────────────────────

  it "rewrites owner: in markdown frontmatter (script→runner)" do
    path = write_file("note.md", "---\nowner: script:cron\ntitle: test\n---\n")
    described_class.run(root: tmpdir)
    expect(File.read(path)).to include("owner: runner:cron")
  end

  it "rewrites owner: ai→agent in markdown" do
    path = write_file("note.md", "---\nowner: ai:catalog\ntitle: test\n---\n")
    described_class.run(root: tmpdir)
    expect(File.read(path)).to include("owner: agent:catalog")
  end

  it "rewrites owner: build→builder in markdown" do
    path = write_file("note.md", "---\nowner: build:foo\n---\n")
    described_class.run(root: tmpdir)
    expect(File.read(path)).to include("owner: builder:foo")
  end

  it "leaves markdown files without an owner line untouched" do
    original = "---\ntitle: no owner\n---\n"
    path = write_file("no_owner.md", original)
    described_class.run(root: tmpdir)
    expect(File.read(path)).to eq(original)
  end

  it "is idempotent for markdown (re-running yields same content)" do
    path = write_file("note.md", "---\nowner: script:cron\ntitle: test\n---\n")
    described_class.run(root: tmpdir)
    first_pass = File.read(path)
    described_class.run(root: tmpdir)
    expect(File.read(path)).to eq(first_pass)
  end

  # ── JSON ─────────────────────────────────────────────────────────────────────

  it "rewrites _meta.owner in JSON files (ai→agent)" do
    doc = { "_meta" => { "owner" => "ai:catalog" }, "data" => "x" }
    path = write_file("entry.json", JSON.generate(doc))
    described_class.run(root: tmpdir)
    result = JSON.parse(File.read(path))
    expect(result["_meta"]["owner"]).to eq("agent:catalog")
  end

  it "rewrites _meta.owner in JSON files (script→runner)" do
    doc = { "_meta" => { "owner" => "script:cron" } }
    path = write_file("entry.json", JSON.generate(doc))
    described_class.run(root: tmpdir)
    result = JSON.parse(File.read(path))
    expect(result["_meta"]["owner"]).to eq("runner:cron")
  end

  it "leaves JSON files without _meta.owner untouched" do
    original = JSON.generate({ "data" => "no meta here" })
    path = write_file("plain.json", original)
    described_class.run(root: tmpdir)
    expect(JSON.parse(File.read(path))).to eq(JSON.parse(original))
  end

  it "silently skips malformed JSON" do
    path = write_file("bad.json", "{ not valid json }")
    expect { described_class.run(root: tmpdir) }.not_to raise_error
    expect(File.read(path)).to eq("{ not valid json }")
  end

  it "is idempotent for JSON" do
    doc = { "_meta" => { "owner" => "ai:catalog" } }
    path = write_file("entry.json", JSON.generate(doc))
    described_class.run(root: tmpdir)
    first_pass = File.read(path)
    described_class.run(root: tmpdir)
    expect(File.read(path)).to eq(first_pass)
  end

  # ── YAML ─────────────────────────────────────────────────────────────────────

  it "rewrites _meta.owner in YAML files (build→builder)" do
    content = "---\n_meta:\n  owner: build:foo\ndata: x\n"
    path = write_file("entry.yaml", content)
    described_class.run(root: tmpdir)
    result = YAML.safe_load_file(path)
    expect(result["_meta"]["owner"]).to eq("builder:foo")
  end

  it "rewrites _meta.owner in .yml files" do
    content = "---\n_meta:\n  owner: script:cron\n"
    path = write_file("entry.yml", content)
    described_class.run(root: tmpdir)
    result = YAML.safe_load_file(path)
    expect(result["_meta"]["owner"]).to eq("runner:cron")
  end

  it "leaves YAML files without _meta.owner untouched" do
    original = "---\ndata: no meta\n"
    path = write_file("plain.yaml", original)
    mtime_before = File.mtime(path)
    described_class.run(root: tmpdir)
    expect(File.mtime(path)).to eq(mtime_before)
  end

  it "silently skips malformed YAML" do
    path = write_file("bad.yaml", "key: [unclosed")
    expect { described_class.run(root: tmpdir) }.not_to raise_error
    expect(File.read(path)).to eq("key: [unclosed")
  end

  it "is idempotent for YAML" do
    content = "---\n_meta:\n  owner: build:foo\n"
    path = write_file("entry.yaml", content)
    described_class.run(root: tmpdir)
    first_pass = File.read(path)
    described_class.run(root: tmpdir)
    expect(File.read(path)).to eq(first_pass)
  end
end
