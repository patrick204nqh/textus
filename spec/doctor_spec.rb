require "spec_helper"
require "tmpdir"
require "fileutils"
require "json"
require "digest"

RSpec.describe Textus::Doctor do
  let(:tmp)  { Dir.mktmpdir }
  let(:root) { File.join(tmp, ".textus") }

  before do
    FileUtils.mkdir_p(File.join(root, "zones/working/notes"))
    FileUtils.mkdir_p(File.join(root, "schemas"))
    FileUtils.mkdir_p(File.join(root, "templates"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/1
      zones:
        - { name: working, writable_by: [human, ai, script] }
        - { name: derived, writable_by: [build] }
      entries:
        - { key: working.notes, path: working/notes, zone: working, schema: note, nested: true }
        - { key: derived.summary, path: derived/summary.md, zone: derived, template: summary.mustache }
    YAML
    File.write(File.join(root, "schemas/note.yaml"), <<~YAML)
      name: note
      required: [name]
      optional: [tag]
      fields:
        name: { type: string, maintained_by: human }
        tag:  { type: string }
    YAML
    File.write(File.join(root, "templates/summary.mustache"), "summary\n")
  end

  after { FileUtils.remove_entry(tmp) }

  def doctor
    store = Textus::Store.new(root)
    described_class.run(store)
  end

  it "reports a clean store as ok: true with no error-level issues" do
    res = doctor
    expect(res["protocol"]).to eq("textus/1")
    expect(res["ok"]).to be true
    expect(res["issues"].any? { |i| i["level"] == "error" }).to be false
  end

  it "reports schema.missing when a schema file is missing" do
    File.delete(File.join(root, "schemas/note.yaml"))
    res = doctor
    issue = res["issues"].find { |i| i["code"] == "schema.missing" }
    expect(issue).not_to be_nil
    expect(issue["level"]).to eq("error")
    expect(issue["fix"]).to include("note")
    expect(res["ok"]).to be false
  end

  it "reports template.missing when a template file is missing" do
    File.delete(File.join(root, "templates/summary.mustache"))
    res = doctor
    issue = res["issues"].find { |i| i["code"] == "template.missing" }
    expect(issue).not_to be_nil
    expect(issue["level"]).to eq("error")
    expect(res["ok"]).to be false
  end

  it "reports extension.load_failed for broken extensions" do
    FileUtils.mkdir_p(File.join(root, "extensions"))
    File.write(File.join(root, "extensions/broken.rb"), <<~RUBY)
      raise "boom from broken extension"
    RUBY
    # Store discovery will fail too — load Doctor directly with a manual store.
    # Use Store.new but rescue its load failure path: since extensions also load
    # at Store#initialize, the broken extension would surface there. Instead
    # bypass by stubbing the directory after store init.
    FileUtils.mkdir_p(File.join(root, "extensions.tmp"))
    File.rename(File.join(root, "extensions"), File.join(root, "extensions.disabled"))
    store = Textus::Store.new(root)
    File.rename(File.join(root, "extensions.disabled"), File.join(root, "extensions"))
    res = described_class.run(store)
    issue = res["issues"].find { |i| i["code"] == "extension.load_failed" }
    expect(issue).not_to be_nil
    expect(issue["level"]).to eq("error")
    expect(issue["subject"]).to eq("broken.rb")
    expect(issue["message"]).to include("boom")
  end

  it "reports key.illegal for nested entries with bad filenames" do
    File.write(File.join(root, "zones/working/notes/Bad_Name.md"), "---\n---\nx\n")
    res = doctor
    issue = res["issues"].find { |i| i["code"] == "key.illegal" }
    expect(issue).not_to be_nil
    expect(issue["proposed_key"]).to eq("bad-name")
    expect(issue["fix"]).to include("migrate-keys")
  end

  it "reports sentinel.orphan when a sentinel's target is missing" do
    FileUtils.mkdir_p(File.join(root, "sentinels"))
    File.write(File.join(root, "sentinels/missing.md.textus-managed.json"), JSON.generate(
                                                                              "source" => "x",
                                                                              "target" => File.join(tmp, "missing.md"),
                                                                              "sha256" => "deadbeef",
                                                                              "mode" => "copy",
                                                                            ))
    res = doctor
    issue = res["issues"].find { |i| i["code"] == "sentinel.orphan" }
    expect(issue).not_to be_nil
    expect(issue["level"]).to eq("warning")
    expect(res["ok"]).to be true # warnings don't flip ok
  end

  it "reports sentinel.drift when the published file's bytes diverge" do
    target = File.join(tmp, "CLAUDE.md")
    File.write(target, "original\n")
    sha = Digest::SHA256.hexdigest("original\n")
    FileUtils.mkdir_p(File.join(root, "sentinels"))
    File.write(File.join(root, "sentinels/CLAUDE.md.textus-managed.json"), JSON.generate(
                                                                             "source" => "x",
                                                                             "target" => target,
                                                                             "sha256" => sha,
                                                                             "mode" => "copy",
                                                                           ))
    File.write(target, "tampered\n") # drift!
    res = doctor
    issue = res["issues"].find { |i| i["code"] == "sentinel.drift" }
    expect(issue).not_to be_nil
    expect(issue["level"]).to eq("warning")
    expect(res["ok"]).to be true
  end

  it "reports audit.parse_error on malformed audit log lines" do
    File.write(File.join(root, "audit.log"), "this is not a tsv row\n")
    res = doctor
    issue = res["issues"].find { |i| i["code"] == "audit.parse_error" }
    expect(issue).not_to be_nil
    expect(issue["level"]).to eq("warning")
  end

  it "reports schema.unowned_fields as info when fields lack maintained_by" do
    res = doctor
    issue = res["issues"].find { |i| i["code"] == "schema.unowned_fields" }
    expect(issue).not_to be_nil
    expect(issue["level"]).to eq("info")
    expect(issue["message"]).to include("tag")
    expect(res["ok"]).to be true
  end

  it "summary tallies issues by level and ok stays true unless an error exists" do
    File.write(File.join(root, "audit.log"), "garbage\n")
    res = doctor
    expect(res["summary"]).to include("error", "warning", "info")
    expect(res["summary"]["warning"]).to be >= 1
    expect(res["ok"]).to be true
  end
end
