require "spec_helper"
require "tmpdir"
require "fileutils"
require "json"
require "open3"

RSpec.describe Textus::Application::Reads::Blame do
  def build_store(repo_root)
    textus = File.join(repo_root, ".textus")
    FileUtils.mkdir_p(File.join(textus, "zones", "working"))
    File.write(File.join(textus, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: working, write_policy: [human, runner] }
      entries:
        - { key: working.doc, path: working/doc.md, zone: working }
    YAML
    Textus::Store.new(textus)
  end

  def write_doc(repo_root, body)
    path = File.join(repo_root, ".textus", "zones", "working", "doc.md")
    File.write(path, "---\nname: doc\n---\n#{body}\n")
    path
  end

  def write_audit(store, row)
    File.open(File.join(store.root, "audit.log"), "a") { |f| f.puts JSON.generate(row) }
  end

  def git(*args, chdir:)
    out, err, status = Open3.capture3("git", *args, chdir: chdir)
    raise "git failed: #{args.inspect}: #{err}" unless status.success?

    out
  end

  it "returns audit rows joined with git commit metadata when path is tracked" do
    Dir.mktmpdir do |repo|
      git("init", "-q", "-b", "main", chdir: repo)
      git("config", "user.email", "t@example.com", chdir: repo)
      git("config", "user.name",  "T Tester",      chdir: repo)
      git("config", "commit.gpgsign", "false", chdir: repo)

      store = build_store(repo)
      write_doc(repo, "v1")
      git("add", "-A", chdir: repo)
      git("commit", "-q", "-m", "initial doc", chdir: repo)

      write_audit(store, { "ts" => Time.now.utc.iso8601, "role" => "human",
                           "verb" => "put", "key" => "working.doc" })

      ctx = Textus::Composition.context(store, role: "human")
      result = Textus::Composition.blame(ctx).call(key: "working.doc")
      expect(result.length).to eq(1)
      row = result.first
      expect(row["git"]).to be_a(Hash)
      expect(row["git"]).to include("sha", "author", "date", "subject")
      expect(row["git"]["subject"]).to eq("initial doc")
    end
  end

  it "returns audit rows with git=>nil when not in a git repo" do
    Dir.mktmpdir do |repo|
      store = build_store(repo)
      write_doc(repo, "v1")
      write_audit(store, { "ts" => Time.now.utc.iso8601, "role" => "human",
                           "verb" => "put", "key" => "working.doc" })

      ctx = Textus::Composition.context(store, role: "human")
      result = Textus::Composition.blame(ctx).call(key: "working.doc")
      expect(result.length).to eq(1)
      expect(result.first["git"]).to be_nil
    end
  end

  it "returns audit rows with git=>nil when file is untracked" do
    Dir.mktmpdir do |repo|
      git("init", "-q", "-b", "main", chdir: repo)
      store = build_store(repo)
      write_doc(repo, "v1") # never committed
      write_audit(store, { "ts" => Time.now.utc.iso8601, "role" => "human",
                           "verb" => "put", "key" => "working.doc" })

      ctx = Textus::Composition.context(store, role: "human")
      result = Textus::Composition.blame(ctx).call(key: "working.doc")
      expect(result.first["git"]).to be_nil
    end
  end
end
