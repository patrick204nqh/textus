require "spec_helper"
require "open3"

RSpec.describe Textus::Action::Blame do
  include_context "textus_store_fixture"

  # `root` is the .textus dir; `tmp` is its parent (the logical "repo root").
  # For tests that need isolated git repos we create subdirs under `tmp`.

  def make_store_at(textus_dir)
    FileUtils.mkdir_p(File.join(textus_dir, "data", "knowledge"))
    File.write(File.join(textus_dir, "manifest.yaml"), <<~YAML)
      version: textus/3
      lanes:
        - { name: knowledge, kind: canon }
      entries:
        - { key: knowledge.doc, path: data/knowledge/doc.md, lane: knowledge, kind: leaf}

    YAML
    Textus::Store.new(textus_dir)
  end

  def write_doc(textus_dir, body)
    path = File.join(textus_dir, "data", "knowledge", "doc.md")
    File.write(path, "---\nname: doc\n---\n#{body}\n")
    path
  end

  def write_audit(store, row)
    FileUtils.mkdir_p(Textus::Layout.audit_dir(store.root))
    File.open(Textus::Layout.audit_log(store.root), "a") { |f| f.puts JSON.generate(row) }
  end

  def git(*args, chdir:)
    out, err, status = Open3.capture3("git", *args, chdir: chdir)
    raise "git failed: #{args.inspect}: #{err}" unless status.success?

    out
  end

  it "returns audit rows joined with git commit metadata when path is tracked" do
    repo = File.join(tmp, "tracked")
    FileUtils.mkdir_p(repo)
    textus_dir = File.join(repo, ".textus")

    git("init", "-q", "-b", "main", chdir: repo)
    git("config", "user.email", "t@example.com", chdir: repo)
    git("config", "user.name",  "T Tester",      chdir: repo)
    git("config", "commit.gpgsign", "false", chdir: repo)

    store = make_store_at(textus_dir)
    write_doc(textus_dir, "v1")
    git("add", "-A", chdir: repo)
    git("commit", "-q", "-m", "initial doc", chdir: repo)

    write_audit(store, { "ts" => Time.now.utc.iso8601, "role" => "human",
                         "verb" => "put", "key" => "knowledge.doc" })

    ops = store.as("human")
    result = ops.blame("knowledge.doc")
    expect(result.length).to eq(1)
    row = result.first
    expect(row["git"]).to be_a(Hash)
    expect(row["git"]).to include("sha", "author", "date", "subject")
    expect(row["git"]["subject"]).to eq("initial doc")
  end

  it "returns audit rows with git=>nil when not in a git repo" do
    repo = File.join(tmp, "no_git")
    textus_dir = File.join(repo, ".textus")
    FileUtils.mkdir_p(textus_dir)

    store = make_store_at(textus_dir)
    write_doc(textus_dir, "v1")
    write_audit(store, { "ts" => Time.now.utc.iso8601, "role" => "human",
                         "verb" => "put", "key" => "knowledge.doc" })

    ops = store.as("human")
    result = ops.blame("knowledge.doc")
    expect(result.length).to eq(1)
    expect(result.first["git"]).to be_nil
  end

  it "returns audit rows with git=>nil when file is untracked" do
    repo = File.join(tmp, "untracked")
    FileUtils.mkdir_p(repo)
    textus_dir = File.join(repo, ".textus")

    git("init", "-q", "-b", "main", chdir: repo)

    store = make_store_at(textus_dir)
    write_doc(textus_dir, "v1") # never committed
    write_audit(store, { "ts" => Time.now.utc.iso8601, "role" => "human",
                         "verb" => "put", "key" => "knowledge.doc" })

    ops = store.as("human")
    result = ops.blame("knowledge.doc")
    expect(result.first["git"]).to be_nil
  end
end
