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
    expect(e.compute).to include("kind" => "projection", "transform" => "marketplace_indexer")
    expect(e.projection).to include("transform" => "marketplace_indexer")
    expect(e.projection).not_to have_key("reduce")
    expect(e.generator).to be_nil
  end

  it "parses compute.kind=external" do
    mf = parse_manifest(<<~YAML)
      - key: output.big
        zone: output
        path: big.json
        format: json
        compute:
          kind: external
          command: "rake build:big-index"
          sources: [working.docs]
    YAML
    e = mf.entries.first
    expect(e.compute["kind"]).to eq("external")
    expect(e.generator).to include("command" => "rake build:big-index")
    expect(e.projection).to be_nil
  end

  it "rejects bare projection: with hint to compute" do
    expect do
      parse_manifest(<<~YAML)
        - key: output.x
          zone: output
          path: x.json
          format: json
          projection:
            select: [working.skills]
      YAML
    end.to raise_error(Textus::BadManifest, /projection:.*compute:.*kind: projection/i)
  end

  it "rejects bare generator: with hint to compute" do
    expect do
      parse_manifest(<<~YAML)
        - key: output.y
          zone: output
          path: y.json
          format: json
          generator:
            command: "rake"
      YAML
    end.to raise_error(Textus::BadManifest, /generator:.*compute:.*kind: external/i)
  end

  it "rejects reduce: inside compute with hint to transform:" do
    expect do
      parse_manifest(<<~YAML)
        - key: output.x
          zone: output
          path: x.json
          format: json
          compute:
            kind: projection
            select: [working.x]
            reduce: f
      YAML
    end.to raise_error(Textus::BadManifest, /reduce.*renamed to.*transform/i)
  end

  it "rejects unknown compute.kind" do
    expect do
      parse_manifest(<<~YAML)
        - key: output.x
          zone: output
          path: x.json
          format: json
          compute:
            kind: weird
      YAML
    end.to raise_error(Textus::BadManifest, /compute\.kind/)
  end
end
