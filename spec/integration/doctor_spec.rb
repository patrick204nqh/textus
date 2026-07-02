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

  it "returns empty issues from doctor summary after workflow migrations" do
    expect(doctor["issues"]).to eq([])
  end

  it "does not include key.illegal in doctor summary (ported to workflow artifact)" do
    File.write(File.join(root, "data/knowledge/notes/Bad_Name.md"), "---\n---\nx\n")
    res = doctor
    issue = res["issues"].find { |i| i["code"] == "key.illegal" }
    expect(issue).to be_nil
  end

  it "does not include sentinel.orphan in doctor summary (ported to workflow artifact)" do
    FileUtils.mkdir_p(File.join(root, ".state", "tracking", "sentinels"))
    File.write(File.join(root, ".state/tracking/sentinels/missing.md.textus-managed.json"), JSON.generate(
                                                                                              "source" => "x",
                                                                                              "target" => File.join(tmp, "missing.md"),
                                                                                              "sha256" => "deadbeef",
                                                                                              "mode" => "copy",
                                                                                            ))
    res = doctor
    issue = res["issues"].find { |i| i["code"] == "sentinel.orphan" }
    expect(issue).to be_nil
  end

  it "does not include sentinel.drift in doctor summary (ported to workflow artifact)" do
    target = File.join(tmp, "CLAUDE.md")
    File.write(target, "original\n")
    sha = Digest::SHA256.hexdigest("original\n")
    FileUtils.mkdir_p(File.join(root, ".state", "tracking", "sentinels"))
    File.write(File.join(root, ".state/tracking/sentinels/CLAUDE.md.textus-managed.json"), JSON.generate(
                                                                                             "source" => "x",
                                                                                             "target" => target,
                                                                                             "sha256" => sha,
                                                                                             "mode" => "copy",
                                                                                           ))
    File.write(target, "tampered\n") # drift!
    res = doctor
    issue = res["issues"].find { |i| i["code"] == "sentinel.drift" }
    expect(issue).to be_nil
  end

  it "does not include audit.parse_error in doctor summary (ported to workflow artifact)" do
    FileUtils.mkdir_p(audit_dir_path(root))
    File.write(audit_log_path(root), "this is not a tsv row\n")
    res = doctor
    issue = res["issues"].find { |i| i["code"] == "audit.parse_error" }
    expect(issue).to be_nil
  end

  it "does not include schema.unowned_fields in doctor summary (ported to workflow artifact)" do
    res = doctor
    issue = res["issues"].find { |i| i["code"] == "schema.unowned_fields" }
    expect(issue).to be_nil
  end

  it "does not include manifest.missing_file in doctor summary (ported to workflow artifact)" do
    FileUtils.rm_f(File.join(root, "data/knowledge/note.md"))
    res = doctor
    issue = res["issues"].find { |i| i["code"] == "manifest.missing_file" }
    expect(issue).to be_nil
  end

  it "does not include schema.missing in doctor summary (ported to workflow artifact)" do
    File.delete(File.join(root, "schemas/note.yaml"))
    res = doctor
    issue = res["issues"].find { |i| i["code"] == "schema.missing" }
    expect(issue).to be_nil
  end

  it "does not include template.missing in doctor summary (ported to workflow artifact)" do
    File.delete(File.join(root, "templates/summary.erb"))
    res = doctor
    issue = res["issues"].find { |i| i["code"] == "template.missing" }
    expect(issue).to be_nil
  end

  it "summary tallies issues by level on the reduced class-check surface" do
    res = doctor
    expect(res["summary"]).to include("error", "warning", "info")
    expect(res["summary"]["warning"]).to eq(0)
    expect(res["ok"]).to be true
  end

  it "does not include rule.ambiguity in doctor summary (ported to workflow artifact)" do
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/4
      lanes:
        - { name: knowledge, kind: canon }
      entries:
        - { key: knowledge.foo, path: knowledge/foo.md, lane: knowledge, kind: leaf}
      rules:
        - match: knowledge.*
          retention: { ttl: 10m, action: drop }
        - match: "*.foo"
          retention: { ttl: 1h, action: archive }
    YAML
    File.write(File.join(root, "data/knowledge/foo.md"), "hi\n")

    res = Textus::Doctor.build(container: Textus::Store.new(root).container)
    issue = res["issues"].find { |i| i["code"] == "rule.ambiguity" }
    expect(issue).to be_nil
  end

  it "does not include proposal.target_not_canon in doctor summary (ported to workflow artifact)" do
    prop_root = File.join(tmp, ".textus-proposal")
    FileUtils.mkdir_p(prop_root)
    store = store_from_manifest(prop_root, lanes: %w[knowledge notebook proposals], manifest: <<~YAML)
      version: textus/4
      roles:
        - { name: human, can: [author, propose] }
        - { name: agent, can: [propose, keep] }
      lanes:
        - { name: knowledge, kind: canon }
        - { name: notebook,  kind: workspace, owner: agent }
        - { name: proposals, kind: queue }
      entries:
        - { key: knowledge.notes, path: knowledge/notes, lane: knowledge, owner: human:self, kind: nested }
        - { key: notebook.notes,  path: notebook/notes,  lane: notebook,  owner: agent:self, kind: nested }
        - { key: proposals.notes, path: proposals/notes, lane: proposals, owner: agent:self, kind: nested }
    YAML
    store.with_role("agent").put(
      key: "proposals.notes.bad",
      meta: { "name" => "bad", "proposal" => { "target_key" => "notebook.notes.bad", "action" => "put" }, "_meta" => { "name" => "bad" } },
      body: "x\n",
    )

    res = Textus::Doctor.build(container: store.container)
    issue = res["issues"].find { |i| i["code"] == "proposal.target_not_canon" }
    expect(issue).to be_nil
  end

  it "does not include generator_drift in doctor summary (ported to workflow artifact)" do # rubocop:disable RSpec/ExampleLength
    FileUtils.mkdir_p(File.join(root, "data/artifacts"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/4
      lanes:
        - { name: knowledge, kind: canon }
        - { name: artifacts, kind: machine }
      entries:
        - key: knowledge.src
          kind: leaf
          path: knowledge/src.md
          lane: knowledge
        - key: artifacts.catalog
          kind: produced
          path: artifacts/catalog.md
          lane: artifacts
          source:
            from: external
            command: "rake catalog"
            sources: [knowledge.src]
    YAML
    File.write(File.join(root, "data/knowledge/src.md"), "---\nname: src\n---\nbody\n")
    File.write(File.join(root, "data/artifacts/catalog.md"), <<~MD)
      ---
      generated:
        by: "rake catalog"
        at: "2020-01-01T00:00:00Z"
        from:
          - knowledge.src
      ---
      catalog
    MD
    File.utime(Time.now, Time.now, File.join(root, "data/knowledge/src.md"))

    res = Textus::Doctor.build(container: Textus::Store.new(root).container)
    issue = res["issues"].find { |i| i["code"] == "generator_drift" }
    expect(issue).to be_nil
  end

  it "does not include raw_asset.missing_file in doctor summary (ported to workflow artifact)" do
    FileUtils.mkdir_p(File.join(root, "data/raw/2026/06/16"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/4
      roles:
        - { name: agent, can: [propose, keep, ingest] }
      lanes:
        - { name: raw, kind: raw }
      entries:
        - { key: raw, lane: raw, owner: agent:self, nested: true, kind: nested, format: yaml }
    YAML
    File.write(
      File.join(root, "data/raw/2026/06/16/asset-missing.yaml"),
      "ingested_at: '2026-06-16T10:00:00Z'\nsource:\n  kind: asset\nasset: raw/2026/06/16/playwright/missing.png\n",
    )

    res = Textus::Doctor.build(container: Textus::Store.new(root).container)
    issue = res["issues"].find { |i| i["code"] == "raw_asset.missing_file" }
    expect(issue).to be_nil
  end

  it "does not include scratchpad.source_missing in doctor summary (ported to workflow artifact)" do
    FileUtils.mkdir_p(File.join(root, "data/scratchpad/notes"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/4
      roles:
        - { name: agent, can: [propose, keep, ingest] }
      lanes:
        - { name: raw, kind: raw }
        - { name: scratchpad, kind: workspace }
      entries:
        - { key: raw, lane: raw, owner: agent:self, nested: true, kind: nested, format: yaml }
        - { key: scratchpad.notes, lane: scratchpad, owner: agent:self, nested: true, kind: nested }
    YAML
    File.write(File.join(root, "data/scratchpad/notes/orphan.md"), "---\nsources:\n  - raw.2026.06.16.url-gone\n---\n\n")

    res = Textus::Doctor.build(container: Textus::Store.new(root).container)
    issue = res["issues"].find { |i| i["code"] == "scratchpad.source_missing" }
    expect(issue).to be_nil
  end

  it "does not include stale_reviewed_stamp in doctor summary (ported to workflow artifact)" do
    current_minor = Textus::VERSION.split(".").map(&:to_i)[1]
    stale_minor = current_minor - 6
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/4
      lanes:
        - { name: knowledge, kind: canon }
      entries:
        - { key: knowledge.doc, lane: knowledge, kind: leaf }
    YAML
    FileUtils.mkdir_p(File.join(root, "data/knowledge"))
    File.write(File.join(root, "data/knowledge/doc.md"), "# Doc\n\n> **SSoT for** x · **reviewed** 2025-01 (v0.#{stale_minor})\n\nbody")

    res = Textus::Doctor.build(container: Textus::Store.new(root).container)
    issue = res["issues"].find { |i| i["code"] == "stale_reviewed_stamp" }
    expect(issue).to be_nil
  end

  it "does not include cursor.expired in doctor summary (ported to workflow artifact)" do
    FileUtils.mkdir_p(File.join(root, ".state", "ephemeral", "cursors"))
    File.write(File.join(root, ".state", "ephemeral", "cursors", "agent"), "7\n")
    FileUtils.mkdir_p(audit_dir_path(root))
    File.write(
      audit_log_path(root),
      [
        "{\"seq\":10,\"ts\":\"2026-01-01T00:00:00Z\",\"role\":\"human\",",
        "\"verb\":\"put\",\"key\":\"knowledge.x\",\"etag_before\":null,",
        "\"etag_after\":\"sha256:x\"}\n",
      ].join,
    )

    res = Textus::Doctor.build(container: Textus::Store.new(root).container)
    issue = res["issues"].find { |i| i["code"] == "cursor.expired" }
    expect(issue).to be_nil
  end

  it "does not include cursor.at_risk in doctor summary (ported to workflow artifact)" do
    keep = 2
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/4
      lanes:
        - { name: knowledge, kind: canon }
      audit:
        keep: #{keep}
      entries:
        - { key: knowledge.note, path: knowledge/note.md, lane: knowledge, kind: leaf}
    YAML
    FileUtils.mkdir_p(File.join(root, "data/knowledge"))
    File.write(File.join(root, "data/knowledge/note.md"), "hi\n")
    FileUtils.mkdir_p(File.join(root, ".state", "ephemeral", "cursors"))
    File.write(File.join(root, ".state", "ephemeral", "cursors", "agent"), "3\n")
    FileUtils.mkdir_p(audit_dir_path(root))
    File.write(File.join(audit_dir_path(root), "audit.log.2.meta.json"), JSON.generate({ "min_seq" => 1, "max_seq" => 5 }))

    res = Textus::Doctor.build(container: Textus::Store.new(root).container)
    issue = res["issues"].find { |i| i["code"] == "cursor.at_risk" }
    expect(issue).to be_nil
  end

  describe "check_schema_violations" do
    let(:tmp2) { Dir.mktmpdir }

    after { FileUtils.remove_entry(tmp2) }

    it "does not include role_authority in doctor summary (ported to workflow artifact)" do
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
      ra_store.with_role("agent").put(key: "proposals.people.alice",
                                      meta: { "name" => "alice", "full_name" => "Alice Wonder", "embedding" => [0.1, 0.2] }, body: "")

      res = Textus::Doctor.build(container: ra_store.container)
      codes = res["issues"].map { |i| i["code"] }
      expect(codes).not_to include("role_authority")
    end
  end

  it "no longer registers the retired cadence-policy checks (ADR 0091/0093)" do
    expect(Textus::Doctor::ALL_CHECKS).not_to include("upkeep_kind_mismatch", "lifecycle_action_invalid")
  end
end
