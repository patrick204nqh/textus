require "spec_helper"
require "digest"

RSpec.describe Textus::Doctor do
  include_context "textus_store_fixture"

  before do
    FileUtils.mkdir_p(File.join(root, "data/knowledge/notes"))
    FileUtils.mkdir_p(File.join(root, "schemas"))
    FileUtils.mkdir_p(File.join(root, "templates"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/4
      lanes:
        - { name: knowledge, kind: canon }
        - { name: artifacts, kind: machine }
      entries:
        - { key: knowledge.notes, path: knowledge/notes, lane: knowledge, schema: note, kind: nested}

        - key: artifacts.summary
          path: artifacts/summary.json
          lane: artifacts
          kind: produced
          source: { from: external, command: "make", sources: [] }
          publish:
            - { to: summary.md, template: summary.erb }

    YAML
    File.write(File.join(root, "schemas/note.yaml"), <<~YAML)
      name: note
      required: [name]
      optional: [tag]
      fields:
        name: { type: string, maintained_by: human }
        tag:  { type: string }
    YAML
    File.write(File.join(root, "templates/summary.erb"), "summary\n")
  end

  def doctor
    store = Textus::Store.new(root)
    described_class.build(container: store.container)
  end

  it "reports a clean store as ok: true with no error-level issues" do
    res = doctor
    expect(res["protocol"]).to eq("textus/4")
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
    File.delete(File.join(root, "templates/summary.erb"))
    res = doctor
    issue = res["issues"].find { |i| i["code"] == "template.missing" }
    expect(issue).not_to be_nil
    expect(issue["level"]).to eq("error")
    expect(res["ok"]).to be false
  end

  it "reports key.illegal for nested entries with bad filenames" do
    File.write(File.join(root, "data/knowledge/notes/Bad_Name.md"), "---\n---\nx\n")
    res = doctor
    issue = res["issues"].find { |i| i["code"] == "key.illegal" }
    expect(issue).not_to be_nil
    expect(issue["message"]).to include("Bad_Name")
    expect(issue["fix"]).to match(/lowercase.*hyphen/i)
  end

  it "reports sentinel.orphan when a sentinel's target is missing" do
    FileUtils.mkdir_p(File.join(root, ".run", "sentinels"))
    File.write(File.join(root, ".run/sentinels/missing.md.textus-managed.json"), JSON.generate(
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
    FileUtils.mkdir_p(File.join(root, ".run", "sentinels"))
    File.write(File.join(root, ".run/sentinels/CLAUDE.md.textus-managed.json"), JSON.generate(
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
    FileUtils.mkdir_p(audit_dir_path(root))
    File.write(audit_log_path(root), "this is not a tsv row\n")
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
    FileUtils.mkdir_p(audit_dir_path(root))
    File.write(audit_log_path(root), "garbage\n")
    res = doctor
    expect(res["summary"]).to include("error", "warning", "info")
    expect(res["summary"]["warning"]).to be >= 1
    expect(res["ok"]).to be true
  end

  describe "check_schema_violations" do
    let(:tmp2) { Dir.mktmpdir }

    after { FileUtils.remove_entry(tmp2) }

    it "surfaces validate_all role_authority violations as error-level issues" do
      ra_root = File.join(tmp2, ".textus")
      FileUtils.mkdir_p(File.join(ra_root, "schemas"))
      FileUtils.mkdir_p(File.join(ra_root, "data/knowledge/people"))

      File.write(File.join(ra_root, "manifest.yaml"), <<~YAML)
        version: textus/4
        lanes:
          - { name: proposals, kind: queue }
        entries:
          - { key: proposals.people, path: proposals/people, lane: proposals, schema: person, owner: human:patrick, kind: nested}

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
      ra_store.as("agent").put(
        "proposals.people.alice",
        meta: { "name" => "alice", "full_name" => "Alice Wonder", "embedding" => [0.1, 0.2] }, body: "",
      )

      res = Textus::Doctor.build(container: ra_store.container, checks: ["schema_violations"])
      codes = res["issues"].map { |i| i["code"] }
      expect(codes).to include("role_authority")
    end
  end

  it "no longer registers the retired cadence-policy checks (ADR 0091/0093)" do
    expect(Textus::Doctor::ALL_CHECKS).not_to include("upkeep_kind_mismatch", "lifecycle_action_invalid")
  end
end
