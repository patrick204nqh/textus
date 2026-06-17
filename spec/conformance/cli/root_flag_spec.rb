# frozen_string_literal: true

require "open3"

RSpec.describe "textus --root" do
  let(:tmp) { Dir.mktmpdir }

  after { FileUtils.rm_rf(tmp) }

  it "uses the --root path for store discovery" do
    custom = File.join(tmp, "store")
    FileUtils.mkdir_p(File.join(custom, "schemas"))
    FileUtils.mkdir_p(File.join(custom, "data"))
    File.write(File.join(custom, "manifest.yaml"),
               "version: textus/4\nlanes:\n  - { name: knowledge, kind: canon }\nentries: []\n")

    exe = File.expand_path("../../../exe/textus", __dir__)
    stdout, _stderr, status = Open3.capture3("ruby", "-I", File.expand_path("../../../lib", __dir__), exe, "--root=#{custom}", "list",
                                             "--output=json")
    expect(status.exitstatus).to eq(0)
    payload = JSON.parse(stdout)
    expect(payload.fetch("entries")).to eq([])
  end

  # F5 (#161): --root is position-agnostic — it works after a verb and after a
  # group subcommand, not only before the verb.
  def store_with_manifest
    custom = File.join(tmp, "store")
    FileUtils.mkdir_p(File.join(custom, "schemas"))
    FileUtils.mkdir_p(File.join(custom, "data"))
    File.write(File.join(custom, "manifest.yaml"),
               "version: textus/4\nlanes:\n  - { name: knowledge, kind: canon }\nentries: []\n")
    custom
  end

  def run_cli(*argv)
    exe = File.expand_path("../../../exe/textus", __dir__)
    Open3.capture3("ruby", "-I", File.expand_path("../../../lib", __dir__), exe, *argv)
  end

  it "accepts --root after the verb (textus list --root=PATH)" do
    custom = store_with_manifest
    stdout, _stderr, status = run_cli("list", "--root=#{custom}", "--output=json")
    expect(status.exitstatus).to eq(0)
    expect(JSON.parse(stdout).fetch("entries")).to eq([])
  end

  it "accepts --root after a group subcommand (textus key uid --root=PATH)" do
    custom = store_with_manifest
    FileUtils.mkdir_p(File.join(custom, "data/knowledge"))
    File.write(File.join(custom, "manifest.yaml"), <<~YAML)
      version: textus/4
      lanes:
        - { name: knowledge, kind: canon }
      entries:
        - { key: knowledge.note, path: knowledge/note.md, lane: knowledge, kind: leaf }
    YAML
    File.write(File.join(custom, "data/knowledge/note.md"), "---\nuid: abc123\n---\nhello\n")
    stdout, _stderr, status = run_cli("key", "uid", "knowledge.note", "--root=#{custom}", "--output=json")
    expect(status.exitstatus).to eq(0)
    expect(JSON.parse(stdout).fetch("uid")).to eq("abc123")
  end

  it "accepts the space form --root PATH after the verb" do
    custom = store_with_manifest
    stdout, _stderr, status = run_cli("list", "--root", custom, "--output=json")
    expect(status.exitstatus).to eq(0)
    expect(JSON.parse(stdout).fetch("entries")).to eq([])
  end

  it "exits non-zero when --root has no manifest" do
    bogus = File.join(tmp, "no-manifest")
    FileUtils.mkdir_p(bogus)
    exe = File.expand_path("../../../exe/textus", __dir__)
    _stdout, stderr, status = Open3.capture3("ruby", "-I", File.expand_path("../../../lib", __dir__), exe, "--root=#{bogus}", "list",
                                             "--output=json")
    expect(status.exitstatus).not_to eq(0)
    expect(stderr).to match(/no textus store/i)
  end
end
