require "spec_helper"

RSpec.describe Textus::Manifest::Entry do
  def parse_manifest(yaml_body)
    Textus::Manifest.parse(<<~YAML)
      version: textus/3
      zones:
        - { name: output, write_policy: [builder] }
      entries:
      #{yaml_body.gsub(/^/, "  ")}
    YAML
  end

  it "parses compute.kind=projection with transform" do
    mf = parse_manifest(<<~YAML)
      - key: output.x
        kind: derived
        zone: output
        path: x.json
        format: json
        compute:
          kind: projection
          select: [working.skills]
          pluck: [name]
          transform: marketplace_indexer
    YAML
    e = mf.entries.first
    expect(e).to be_a(Textus::Manifest::Entry::Derived)
    expect(e).to be_projection
    expect(e.source.transform).to eq("marketplace_indexer")
    expect(e.source.select).to eq(["working.skills"])
  end

  it "parses compute.kind=external" do
    mf = parse_manifest(<<~YAML)
      - key: output.big
        kind: derived
        zone: output
        path: big.json
        format: json
        compute:
          kind: external
          command: "rake build:big-index"
          sources: [working.docs]
    YAML
    e = mf.entries.first
    expect(e).to be_a(Textus::Manifest::Entry::Derived)
    expect(e).to be_external
    expect(e.source.runner).to be_nil
  end

  it "rejects unknown compute.kind" do
    expect do
      parse_manifest(<<~YAML)
        - key: output.x
          kind: derived
          zone: output
          path: x.json
          format: json
          compute:
            kind: weird
      YAML
    end.to raise_error(Textus::BadManifest, /compute\.kind/)
  end
end
