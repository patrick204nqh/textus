require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe "Manifest index_filename: surfaces a fixed basename as the per-directory row" do
  include_context "textus_store_fixture"

  before do
    FileUtils.mkdir_p(File.join(root, "zones/skills/ask"))
    FileUtils.mkdir_p(File.join(root, "zones/skills/ask/references"))
    FileUtils.mkdir_p(File.join(root, "zones/skills/do"))

    File.write(File.join(root, "zones/skills/ask/SKILL.md"), "---\nname: ask\n---\nbody ask")
    File.write(File.join(root, "zones/skills/ask/references/algorithm.md"), "---\nname: algorithm\n---\nbody algo")
    File.write(File.join(root, "zones/skills/do/SKILL.md"), "---\nname: do\n---\nbody do")
  end

  def write_manifest(entries_yaml)
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/2
      zones:
        - { name: skills, writable_by: [human] }
      entries:
      #{entries_yaml}
    YAML
  end

  it "enumerates SKILL.md files keyed by parent directory" do
    write_manifest("  - { key: skills, path: skills, zone: skills, nested: true, index_filename: SKILL.md }")

    rows = Textus::Manifest.load(root).enumerate
    keys = rows.map { |r| r[:key] }

    expect(keys).to contain_exactly("skills.ask", "skills.do")
  end

  it "ignores sibling files (references/*) under index_filename mode" do
    write_manifest("  - { key: skills, path: skills, zone: skills, nested: true, index_filename: SKILL.md }")

    rows = Textus::Manifest.load(root).enumerate
    paths = rows.map { |r| File.basename(r[:path]) }

    expect(paths).to all(eq("SKILL.md"))
  end

  it "resolve(key) returns the SKILL.md path for a sub-directory" do
    write_manifest("  - { key: skills, path: skills, zone: skills, nested: true, index_filename: SKILL.md }")

    _entry, path, _remaining = Textus::Manifest.load(root).resolve("skills.ask")

    expect(path).to eq(File.join(root, "zones/skills/ask/SKILL.md"))
  end

  it "rejects index_filename without nested: true" do
    write_manifest("  - { key: skills, path: skills/ask/SKILL.md, zone: skills, index_filename: SKILL.md }")

    expect { Textus::Manifest.load(root) }
      .to raise_error(Textus::UsageError, /requires nested: true/)
  end

  it "rejects index_filename with a slash" do
    write_manifest("  - { key: skills, path: skills, zone: skills, nested: true, index_filename: refs/SKILL.md }")

    expect { Textus::Manifest.load(root) }
      .to raise_error(Textus::UsageError, /must be a bare basename/)
  end

  it "rejects index_filename whose extension does not match the format" do
    write_manifest("  - { key: skills, path: skills, zone: skills, nested: true, format: markdown, index_filename: SKILL.json }")

    expect { Textus::Manifest.load(root) }
      .to raise_error(Textus::UsageError, /implies format "json"/)
  end

  it "rejects index_filename with an unknown extension" do
    write_manifest("  - { key: skills, path: skills, zone: skills, nested: true, index_filename: SKILL.weird }")

    expect { Textus::Manifest.load(root) }
      .to raise_error(Textus::UsageError, /unknown extension/)
  end
end
