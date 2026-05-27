require "spec_helper"

RSpec.describe Textus::Application::Tools::MigrateManifestToKinds do
  it "infers kinds from 0.19 manifest fields" do
    yaml = <<~YAML
      version: textus/3
      zones: [{ name: z, write_policy: [human] }]
      entries:
        - { key: z.notes, path: z/notes.md, owner: h, kind: leaf}

        - { key: z.people, path: z/people, owner: h, nested: true, kind: nested}

        - { key: z.x, path: z/x.md, owner: builder:auto, template: x.mustache,
            compute: { kind: projection, select: z.people } }
        - { key: z.feed, path: z/feed.json, owner: runner,
            intake: { handler: fetch_feed } }
    YAML

    kinds = YAML.safe_load(described_class.upgrade_yaml(yaml))["entries"]
                .to_h { |e| [e["key"], e["kind"]] }
    expect(kinds).to eq(
      "z.notes" => "leaf",
      "z.people" => "nested",
      "z.x" => "derived",
      "z.feed" => "intake",
    )
  end

  it "leaves rows that already declare kind: alone" do
    yaml = <<~YAML
      version: textus/3
      zones: [{ name: z, write_policy: [human] }]
      entries:
        - { key: z.a, path: z/a.md, zone: z, kind: leaf, owner: h }
    YAML
    out = described_class.upgrade_yaml(yaml)
    expect(YAML.safe_load(out)["entries"].first["kind"]).to eq("leaf")
  end
end
