require "spec_helper"

RSpec.describe "Manifest format: field validation" do
  include_context "textus_store_fixture"

  before do
    FileUtils.mkdir_p(File.join(root, "data/knowledge"))
    FileUtils.mkdir_p(File.join(root, "data/artifacts"))
  end

  def write_manifest(entries_yaml)
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      lanes:
        - { name: knowledge, kind: canon }
        - { name: artifacts, kind: machine }
      entries:
      #{entries_yaml}
    YAML
  end

  it "rejects .md path with format: json" do
    write_manifest("  - { key: knowledge.x, path: data/knowledge/x.md, lane: knowledge, format: json, kind: leaf }")
    expect { Textus::Manifest.load(root) }
      .to raise_error(Textus::UsageError, /does not match declared format/)
  end

  it "infers format: json from .json extension when not declared" do
    write_manifest("  - { key: knowledge.x, path: data/knowledge/x.json, lane: knowledge, kind: leaf }")
    m = Textus::Manifest.load(root)
    expect(m.data.entries.first.format).to eq("json")
  end

  it "infers format: yaml from .yaml" do
    write_manifest("  - { key: knowledge.x, path: data/knowledge/x.yaml, lane: knowledge, kind: leaf }")
    expect(Textus::Manifest.load(root).data.entries.first.format).to eq("yaml")
  end

  it "infers format: yaml from .yml" do
    write_manifest("  - { key: knowledge.x, path: data/knowledge/x.yml, lane: knowledge, kind: leaf }")
    expect(Textus::Manifest.load(root).data.entries.first.format).to eq("yaml")
  end

  it "infers format: text from .txt" do
    write_manifest("  - { key: knowledge.x, path: data/knowledge/x.txt, lane: knowledge, kind: leaf }")
    expect(Textus::Manifest.load(root).data.entries.first.format).to eq("text")
  end

  it "defaults to markdown when no extension on leaf" do
    write_manifest("  - { key: knowledge.x, path: data/knowledge/x, lane: knowledge, kind: leaf }")
    expect(Textus::Manifest.load(root).data.entries.first.format).to eq("markdown")
  end

  it "accepts a derived projection without any publish template (rendering is a publish concern, ADR 0094)" do
    write_manifest(<<~YAML)
      - key: artifacts.x
        kind: produced
        path: data/artifacts/x.json
        lane: artifacts
        source: { from: external, command: "make", sources: [] }
    YAML
    expect { Textus::Manifest.load(root) }.not_to raise_error
  end

  it "rejects text format with a schema" do
    write_manifest("  - { key: knowledge.x, path: data/knowledge/x.txt, lane: knowledge, format: text, schema: foo, kind: leaf }")
    expect { Textus::Manifest.load(root) }
      .to raise_error(Textus::UsageError, /text format must not declare a schema/)
  end

  it "globs both .yaml and .yml for nested yaml entries" do
    write_manifest(<<~YAML)
      - { key: knowledge.cfg, path: data/knowledge/cfg, lane: knowledge, format: yaml, kind: nested }
    YAML
    base = File.join(root, "data/knowledge/cfg")
    FileUtils.mkdir_p(base)
    File.write(File.join(base, "alpha.yaml"), "k: 1\n")
    File.write(File.join(base, "beta.yml"), "k: 2\n")

    manifest = Textus::Manifest.load(root)
    keys = manifest.resolver.enumerate.map { |r| r[:key] }.sort
    expect(keys).to eq(%w[knowledge.cfg.alpha knowledge.cfg.beta])
  end

  it "resolves nested json paths with .json extension" do
    write_manifest(<<~YAML)
      - { key: knowledge.cfg, path: data/knowledge/cfg, lane: knowledge, format: json, kind: nested }
    YAML
    manifest = Textus::Manifest.load(root)
    path = manifest.resolver.resolve("knowledge.cfg.alpha").path
    expect(path).to end_with("data/knowledge/cfg/alpha.json")
  end
end
