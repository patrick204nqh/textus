require "spec_helper"
require "tmpdir"
require "fileutils"
require "json"
require "digest"

RSpec.describe Textus::Doctor do
  include_context "textus_store_fixture"

  before do
    FileUtils.mkdir_p(File.join(root, "zones/working/notes"))
    FileUtils.mkdir_p(File.join(root, "schemas"))
    FileUtils.mkdir_p(File.join(root, "templates"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: working, write_policy: [human, agent, runner] }
        - { name: output, write_policy: [builder] }
      entries:
        - { key: working.notes, path: working/notes, zone: working, schema: note, nested: true, kind: nested}

        - { key: output.summary, path: output/summary.md, zone: output, template: summary.mustache, kind: derived, compute: { kind: projection }}

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

  def doctor
    store = Textus::Store.new(root)
    described_class.run(Textus::Session.for(store))
  end

  it "reports a clean store as ok: true with no error-level issues" do
    res = doctor
    expect(res["protocol"]).to eq("textus/3")
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

  it "reports hook.load_failed for broken hook files" do
    FileUtils.mkdir_p(File.join(root, "hooks"))
    # Store#load_hooks also loads from hooks/ and raises on load error,
    # so we move the broken file out of the way during Store.new, then move
    # it back before doctor runs.
    File.write(File.join(root, "hooks/broken.rb"), <<~RUBY)
      raise "boom from broken hook"
    RUBY
    File.rename(File.join(root, "hooks"), File.join(root, "hooks.disabled"))
    store = Textus::Store.new(root)
    File.rename(File.join(root, "hooks.disabled"), File.join(root, "hooks"))
    res = described_class.run(Textus::Session.for(store))
    issue = res["issues"].find { |i| i["code"] == "hook.load_failed" }
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
    expect(issue["message"]).to include("Bad_Name")
    expect(issue["fix"]).to match(/lowercase.*hyphen/i)
  end

  context "with index_filename on a nested entry" do
    before do
      FileUtils.mkdir_p(File.join(root, "zones/skills/ask/references"))
      FileUtils.mkdir_p(File.join(root, "zones/skills/Bad_Name"))
      File.write(File.join(root, "manifest.yaml"), <<~YAML)
        version: textus/3
        zones:
          - { name: working, write_policy: [human, agent, runner] }
          - { name: skills, write_policy: [human] }
          - { name: output, write_policy: [builder] }
        entries:
          - { key: working.notes, path: working/notes, zone: working, schema: note, nested: true, kind: nested}

          - { key: output.summary, path: output/summary.md, zone: output, template: summary.mustache, kind: derived, compute: { kind: projection }}

          - { key: skills, path: skills, zone: skills, nested: true, index_filename: SKILL.md, kind: nested}

      YAML
    end

    it "does not flag SKILL.md (uppercase index filename) as illegal" do
      File.write(File.join(root, "zones/skills/ask/SKILL.md"), "---\nname: ask\n---\nbody")
      res = doctor
      illegal = res["issues"].select { |i| i["code"] == "key.illegal" }
      expect(illegal).to be_empty
    end

    it "does not flag sibling files under references/ that aren't enumerated" do
      File.write(File.join(root, "zones/skills/ask/SKILL.md"), "---\nname: ask\n---\n")
      File.write(File.join(root, "zones/skills/ask/references/Bad_Sibling.md"), "---\n---\n")
      res = doctor
      bad = res["issues"].select { |i| i["code"] == "key.illegal" && i["message"].include?("Bad_Sibling") }
      expect(bad).to be_empty
    end

    it "still flags a parent directory whose name is an illegal segment" do
      File.write(File.join(root, "zones/skills/Bad_Name/SKILL.md"), "---\nname: bad\n---\n")
      res = doctor
      issue = res["issues"].find { |i| i["code"] == "key.illegal" }
      expect(issue).not_to be_nil
      expect(issue["message"]).to include("Bad_Name")
    end
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

  it "reports hook.check_failed with a fix hint pointing to .textus/hooks/" do
    FileUtils.mkdir_p(File.join(root, "hooks"))
    File.write(File.join(root, "hooks/bad_check.rb"), <<~RUBY)
      Textus.hook do |reg|
        reg.on(:validate, :bad_check) { |store:| raise "boom in check" }
      end
    RUBY
    store = Textus::Store.new(root)
    res = described_class.run(Textus::Session.for(store))
    issue = res["issues"].find { |i| i["code"] == "doctor_check.failed" }
    expect(issue).not_to be_nil
    expect(issue["fix"]).to include(".textus/hooks/")
    expect(issue["fix"]).not_to include(".textus/extensions/")
  end

  describe "check_schema_violations" do
    let(:tmp2) { Dir.mktmpdir }

    after { FileUtils.remove_entry(tmp2) }

    it "surfaces validate_all role_authority violations as error-level issues" do
      ra_root = File.join(tmp2, ".textus")
      FileUtils.mkdir_p(File.join(ra_root, "schemas"))
      FileUtils.mkdir_p(File.join(ra_root, "zones/working/people"))

      File.write(File.join(ra_root, "manifest.yaml"), <<~YAML)
        version: textus/3
        zones:
          - { name: working, write_policy: [human, agent, runner] }
        entries:
          - { key: working.people, path: working/people, zone: working, schema: person, owner: human:patrick, nested: true, kind: nested}

      YAML

      File.write(File.join(ra_root, "schemas/person.yaml"), <<~YAML)
        name: person
        required: [full_name]
        fields:
          full_name:  { type: string, maintained_by: human }
          embedding:  { type: array,  maintained_by: ai }
      YAML

      ra_store = Textus::Store.new(ra_root)
      # Write full_name as ai — violates maintained_by: human
      Textus::Session.for(ra_store, role: "agent").put(
        "working.people.alice",
        meta: { "name" => "alice", "full_name" => "Alice Wonder", "embedding" => [0.1, 0.2] }, body: "",
      )

      res = Textus::Doctor.run(Textus::Session.for(ra_store), checks: ["schema_violations"])
      codes = res["issues"].map { |i| i["code"] }
      expect(codes).to include("role_authority")
    end
  end
end
