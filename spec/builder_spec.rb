require "spec_helper"
require "fileutils"
require "json"
require "tmpdir"
require "yaml"

RSpec.describe Textus::Application::Writes::Build do
  include_context "textus_store_fixture"

  let(:store) { Textus::Store.new(root) }
  let(:build_use_case) do
    ctx = Textus::Composition.context(store, role: "build")
    Textus::Composition.writes_build(ctx)
  end

  before do
    FileUtils.mkdir_p(File.join(root, "zones/working/people"))
    FileUtils.mkdir_p(File.join(root, "zones/output"))
    FileUtils.mkdir_p(File.join(root, "templates"))

    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/2
      zones:
        - { name: working, writable_by: [human, ai, script] }
        - { name: output, writable_by: [build] }
      entries:
        - { key: working.people, path: working/people, zone: working, schema: null, owner: o, nested: true }
        - key: output.catalogs.people
          path: output/catalogs/people.md
          zone: output
          schema: null
          owner: build:auto
          projection: { select: working.people, pluck: [name, org], sort_by: name }
          template: people.mustache
          publish_to: [PEOPLE.md]
        - key: output.people-json
          path: output/people.json
          zone: output
          format: json
          schema: null
          owner: build:auto
          projection: { select: working.people, pluck: [name, org], sort_by: name }
        - key: output.people-yaml
          path: output/people.yaml
          zone: output
          format: yaml
          schema: null
          owner: build:auto
          projection: { select: working.people, pluck: [name, org], reduce: envelope }
        - key: output.people-json-tpl
          path: output/people-tpl.json
          zone: output
          format: json
          schema: null
          owner: build:auto
          projection: { select: working.people, pluck: [name, org], sort_by: name }
          template: people.json.mustache
        - key: output.people-bad-tpl
          path: output/people-bad.json
          zone: output
          format: json
          schema: null
          owner: build:auto
          projection: { select: working.people, pluck: [name, org], sort_by: name }
          template: people-bad.json.mustache
    YAML

    File.write(File.join(root, "zones/working/people/alice.md"),
               "---\nname: alice\norg: x\n---\n")
    File.write(File.join(root, "zones/working/people/bob.md"),
               "---\nname: bob\norg: y\n---\n")
    File.write(File.join(root, "templates/people.mustache"),
               "{{#entries}}- {{name}} ({{org}})\n{{/entries}}")
    File.write(File.join(root, "templates/people.json.mustache"), <<~MUSTACHE)
      {
        "people": [
          {{#entries}}{ "name": "{{name}}", "org": "{{org}}" }{{^_last}},{{/_last}}
          {{/entries}}
        ]
      }
    MUSTACHE
    File.write(File.join(root, "templates/people-bad.json.mustache"),
               "{ this is not json")

    # Reducer used by the YAML pipeline — returns a Hash so the structured-format
    # path uses it as the payload base.
    store.registry.register(:reduce, :envelope) do |store:, rows:, config:|
      _ = config
      _ = store
      { "protocol" => "textus/2", "people" => rows.sort_by { |r| r["name"].to_s } }
    end
  end

  it "materializes an output markdown entry and publishes a copy" do
    res = build_use_case.call(prefix: "output.catalogs.people")
    expect(res["built"].map { |b| b["key"] }).to include("output.catalogs.people")
    body = File.read(File.join(root, "zones/output/catalogs/people.md"))
    expect(body).to include("- alice (x)")
    expect(body).to include("- bob (y)")
    # Existing frontmatter contract: generated.at still present in markdown.
    parsed = Textus::Entry.for_format("markdown").parse(body, path: nil)
    expect(parsed["_meta"]["generated"]).to be_a(Hash)
    expect(parsed["_meta"]["generated"]["at"]).to match(/\dT\d/)

    published = File.join(File.dirname(root), "PEOPLE.md")
    sentinel = File.join(root, "sentinels", "PEOPLE.md.textus-managed.json")
    expect(File.exist?(sentinel)).to be true
    expect(File.symlink?(published)).to be false
    expect(File.binread(published)).to eq(File.binread(File.join(root, "zones/output/catalogs/people.md")))
  end

  it "materializes a templateless JSON entry with _meta injected first" do
    build_use_case.call(prefix: "output.people-json")
    raw = File.read(File.join(root, "zones/output/people.json"))
    parsed = JSON.parse(raw)

    expect(parsed.keys.first).to eq("_meta")
    expect(parsed["_meta"].keys).to eq(%w[generated_at from])
    expect(parsed["_meta"]["from"]).to eq(["working.people"])
    expect(parsed["entries"]).to be_an(Array)
    expect(parsed["entries"].map { |r| r["name"] }).to contain_exactly("alice", "bob")
  end

  it "materializes a templateless YAML entry whose reducer shapes the body" do
    build_use_case.call(prefix: "output.people-yaml")
    raw = File.read(File.join(root, "zones/output/people.yaml"))
    parsed = YAML.safe_load(raw, aliases: false)

    expect(parsed.keys.first).to eq("_meta")
    expect(parsed["_meta"].keys).to eq(%w[generated_at from reduce])
    expect(parsed["_meta"]["reduce"]).to eq("envelope")
    expect(parsed["protocol"]).to eq("textus/2")
    expect(parsed["people"].map { |r| r["name"] }).to contain_exactly("alice", "bob")
  end

  it "supports the JSON template escape hatch and injects _meta first" do
    build_use_case.call(prefix: "output.people-json-tpl")
    raw = File.read(File.join(root, "zones/output/people-tpl.json"))
    parsed = JSON.parse(raw)

    expect(parsed.keys.first).to eq("_meta")
    expect(parsed["_meta"].keys).to eq(%w[generated_at from template])
    expect(parsed["_meta"]["template"]).to eq("people.json.mustache")
    expect(parsed["people"].map { |r| r["name"] }).to contain_exactly("alice", "bob")
  end

  it "raises bad_render when a JSON template renders invalid JSON" do
    expect { build_use_case.call(prefix: "output.people-bad-tpl") }
      .to raise_error(Textus::BadRender) { |e| expect(e.code).to eq("bad_render") }
  end
end
