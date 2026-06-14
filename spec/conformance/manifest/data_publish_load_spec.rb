# spec/integration/manifest/data_publish_load_spec.rb
require "spec_helper"

RSpec.describe "data/publish manifest load (ADR 0094)" do
  include_context "textus_store_fixture"

  def load(manifest)
    store_from_manifest(root, lanes: %w[knowledge artifacts], manifest: manifest).manifest
  end

  it "rejects entry-level template: (rendering is a publish concern)" do
    yaml = <<~YAML
      version: textus/3
      lanes: [{ name: artifacts, kind: machine }, { name: knowledge, kind: canon }]
      entries:
        - key: artifacts.x
          kind: produced
          path: data/artifacts/x.json
          lane: artifacts
          template: c.mustache
          source: { from: derive, select: [knowledge.a] }
    YAML
    expect { load(yaml) }.to raise_error(Textus::BadManifest, /template.*publish|ADR 0094/i)
  end

  it "rejects entry-level inject_boot:" do
    yaml = <<~YAML
      version: textus/3
      lanes: [{ name: artifacts, kind: machine }, { name: knowledge, kind: canon }]
      entries:
        - key: artifacts.x
          kind: produced
          path: data/artifacts/x.json
          lane: artifacts
          inject_boot: true
          source: { from: derive, select: [knowledge.a] }
    YAML
    expect { load(yaml) }.to raise_error(Textus::BadManifest, /inject_boot/i)
  end

  it "accepts a flat project source with a publish list" do
    yaml = <<~YAML
      version: textus/3
      lanes: [{ name: artifacts, kind: machine }, { name: knowledge, kind: canon }]
      entries:
        - key: artifacts.x
          kind: produced
          path: data/artifacts/x.json
          lane: artifacts
          source: { from: derive, select: [knowledge.a], transform: r }
          publish:
            - { to: OUT.md, template: c.mustache, inject_boot: true }
            - { to: out.json }
    YAML
    e = load(yaml).data.entries.find { |x| x.key == "artifacts.x" }
    expect(e.publish_targets.map(&:to)).to eq(["OUT.md", "out.json"])
  end
end
