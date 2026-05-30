require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe "Manifest format: field validation" do
  include_context "textus_store_fixture"

  before do
    FileUtils.mkdir_p(File.join(root, "zones/working"))
    FileUtils.mkdir_p(File.join(root, "zones/output"))
  end

  def write_manifest(entries_yaml)
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: working, kind: origin }
        - { name: output, kind: derived }
      entries:
      #{entries_yaml}
    YAML
  end

  it "rejects .md path with format: json" do
    write_manifest("  - { key: working.x, path: working/x.md, zone: working, format: json, kind: leaf }")
    expect { Textus::Manifest.load(root) }
      .to raise_error(Textus::UsageError, /does not match declared format/)
  end

  it "infers format: json from .json extension when not declared" do
    write_manifest("  - { key: working.x, path: working/x.json, zone: working, kind: leaf }")
    m = Textus::Manifest.load(root)
    expect(m.data.entries.first.format).to eq("json")
  end

  it "infers format: yaml from .yaml" do
    write_manifest("  - { key: working.x, path: working/x.yaml, zone: working, kind: leaf }")
    expect(Textus::Manifest.load(root).data.entries.first.format).to eq("yaml")
  end

  it "infers format: yaml from .yml" do
    write_manifest("  - { key: working.x, path: working/x.yml, zone: working, kind: leaf }")
    expect(Textus::Manifest.load(root).data.entries.first.format).to eq("yaml")
  end

  it "infers format: text from .txt" do
    write_manifest("  - { key: working.x, path: working/x.txt, zone: working, kind: leaf }")
    expect(Textus::Manifest.load(root).data.entries.first.format).to eq("text")
  end

  it "defaults to markdown when no extension on leaf" do
    write_manifest("  - { key: working.x, path: working/x, zone: working, kind: leaf }")
    expect(Textus::Manifest.load(root).data.entries.first.format).to eq("markdown")
  end

  it "rejects output markdown without template" do
    write_manifest(<<~YAML)
      - key: output.x
        kind: derived
        path: output/x.md
        zone: output
        compute: { kind: projection, select: [working] }
    YAML
    expect { Textus::Manifest.load(root) }
      .to raise_error(Textus::UsageError, /markdown entries in a generator zone require a template/)
  end

  it "accepts output json without template (templateless escape hatch is also OK)" do
    write_manifest(<<~YAML)
      - key: output.x
        kind: derived
        path: output/x.json
        zone: output
        compute: { kind: projection, select: [working] }
    YAML
    expect { Textus::Manifest.load(root) }.not_to raise_error
  end

  it "rejects text format with a schema" do
    write_manifest("  - { key: working.x, path: working/x.txt, zone: working, format: text, schema: foo, kind: leaf }")
    expect { Textus::Manifest.load(root) }
      .to raise_error(Textus::UsageError, /text format must not declare a schema/)
  end

  it "globs both .yaml and .yml for nested yaml entries" do
    write_manifest(<<~YAML)
      - { key: working.cfg, path: working/cfg, zone: working, format: yaml, nested: true, kind: nested }
    YAML
    base = File.join(root, "zones/working/cfg")
    FileUtils.mkdir_p(base)
    File.write(File.join(base, "alpha.yaml"), "k: 1\n")
    File.write(File.join(base, "beta.yml"), "k: 2\n")

    manifest = Textus::Manifest.load(root)
    keys = manifest.resolver.enumerate.map { |r| r[:key] }.sort
    expect(keys).to eq(%w[working.cfg.alpha working.cfg.beta])
  end

  it "resolves nested json paths with .json extension" do
    write_manifest(<<~YAML)
      - { key: working.cfg, path: working/cfg, zone: working, format: json, nested: true, kind: nested }
    YAML
    manifest = Textus::Manifest.load(root)
    path = manifest.resolver.resolve("working.cfg.alpha").path
    expect(path).to end_with("zones/working/cfg/alpha.json")
  end
end
