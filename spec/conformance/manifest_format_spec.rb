require "spec_helper"

RSpec.describe "Manifest format: field validation" do
  include_context "textus_store_fixture"

  before do
    FileUtils.mkdir_p(File.join(root, "zones/knowledge"))
    FileUtils.mkdir_p(File.join(root, "zones/artifacts"))
  end

  def write_manifest(entries_yaml)
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: knowledge, kind: canon }
        - { name: artifacts, kind: machine }
      entries:
      #{entries_yaml}
    YAML
  end

  it "rejects .md path with format: json" do
    write_manifest("  - { key: knowledge.x, path: knowledge/x.md, zone: knowledge, format: json, kind: leaf }")
    expect { Textus::Manifest.load(root) }
      .to raise_error(Textus::UsageError, /does not match declared format/)
  end

  it "infers format: json from .json extension when not declared" do
    write_manifest("  - { key: knowledge.x, path: knowledge/x.json, zone: knowledge, kind: leaf }")
    m = Textus::Manifest.load(root)
    expect(m.data.entries.first.format).to eq("json")
  end

  it "infers format: yaml from .yaml" do
    write_manifest("  - { key: knowledge.x, path: knowledge/x.yaml, zone: knowledge, kind: leaf }")
    expect(Textus::Manifest.load(root).data.entries.first.format).to eq("yaml")
  end

  it "infers format: yaml from .yml" do
    write_manifest("  - { key: knowledge.x, path: knowledge/x.yml, zone: knowledge, kind: leaf }")
    expect(Textus::Manifest.load(root).data.entries.first.format).to eq("yaml")
  end

  it "infers format: text from .txt" do
    write_manifest("  - { key: knowledge.x, path: knowledge/x.txt, zone: knowledge, kind: leaf }")
    expect(Textus::Manifest.load(root).data.entries.first.format).to eq("text")
  end

  it "defaults to markdown when no extension on leaf" do
    write_manifest("  - { key: knowledge.x, path: knowledge/x, zone: knowledge, kind: leaf }")
    expect(Textus::Manifest.load(root).data.entries.first.format).to eq("markdown")
  end

  it "rejects markdown output without template" do
    write_manifest(<<~YAML)
      - key: artifacts.x
        kind: derived
        path: artifacts/x.md
        zone: artifacts
        compute: { kind: projection, select: [knowledge] }
    YAML
    expect { Textus::Manifest.load(root) }
      .to raise_error(Textus::UsageError, /markdown entries in a generator zone require a template/)
  end

  it "accepts json output without template (templateless escape hatch is also OK)" do
    write_manifest(<<~YAML)
      - key: artifacts.x
        kind: derived
        path: artifacts/x.json
        zone: artifacts
        compute: { kind: projection, select: [knowledge] }
    YAML
    expect { Textus::Manifest.load(root) }.not_to raise_error
  end

  it "rejects text format with a schema" do
    write_manifest("  - { key: knowledge.x, path: knowledge/x.txt, zone: knowledge, format: text, schema: foo, kind: leaf }")
    expect { Textus::Manifest.load(root) }
      .to raise_error(Textus::UsageError, /text format must not declare a schema/)
  end

  it "globs both .yaml and .yml for nested yaml entries" do
    write_manifest(<<~YAML)
      - { key: knowledge.cfg, path: knowledge/cfg, zone: knowledge, format: yaml, kind: nested }
    YAML
    base = File.join(root, "zones/knowledge/cfg")
    FileUtils.mkdir_p(base)
    File.write(File.join(base, "alpha.yaml"), "k: 1\n")
    File.write(File.join(base, "beta.yml"), "k: 2\n")

    manifest = Textus::Manifest.load(root)
    keys = manifest.resolver.enumerate.map { |r| r[:key] }.sort
    expect(keys).to eq(%w[knowledge.cfg.alpha knowledge.cfg.beta])
  end

  it "resolves nested json paths with .json extension" do
    write_manifest(<<~YAML)
      - { key: knowledge.cfg, path: knowledge/cfg, zone: knowledge, format: json, kind: nested }
    YAML
    manifest = Textus::Manifest.load(root)
    path = manifest.resolver.resolve("knowledge.cfg.alpha").path
    expect(path).to end_with("zones/knowledge/cfg/alpha.json")
  end
end
