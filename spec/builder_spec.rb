require "spec_helper"
require "fileutils"
require "json"
require "tmpdir"
require "yaml"

RSpec.describe Textus::Builder do
  let(:tmp)  { Dir.mktmpdir }
  let(:root) { File.join(tmp, ".textus") }
  let(:store) { Textus::Store.new(root) }

  before do
    FileUtils.mkdir_p(File.join(root, "zones/working/people"))
    FileUtils.mkdir_p(File.join(root, "zones/derived"))
    FileUtils.mkdir_p(File.join(root, "templates"))

    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/2
      zones:
        - { name: working, writable_by: [human, ai, script] }
        - { name: derived, writable_by: [build] }
      entries:
        - { key: working.people, path: working/people, zone: working, schema: null, owner: o, nested: true }
        - key: derived.catalogs.people
          path: derived/catalogs/people.md
          zone: derived
          schema: null
          owner: build:auto
          projection: { select: working.people, pluck: [name, org], sort_by: name }
          template: people.mustache
          publish_to: [PEOPLE.md]
        - key: derived.people-json
          path: derived/people.json
          zone: derived
          format: json
          schema: null
          owner: build:auto
          projection: { select: working.people, pluck: [name, org], sort_by: name }
        - key: derived.people-yaml
          path: derived/people.yaml
          zone: derived
          format: yaml
          schema: null
          owner: build:auto
          projection: { select: working.people, pluck: [name, org], reduce: envelope }
        - key: derived.people-json-tpl
          path: derived/people-tpl.json
          zone: derived
          format: json
          schema: null
          owner: build:auto
          projection: { select: working.people, pluck: [name, org], sort_by: name }
          template: people.json.mustache
        - key: derived.people-bad-tpl
          path: derived/people-bad.json
          zone: derived
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

  after { FileUtils.remove_entry(tmp) }

  it "materializes a derived markdown entry and publishes a copy" do
    res = Textus::Builder.new(store).build(prefix: "derived.catalogs.people")
    expect(res["built"].map { |b| b["key"] }).to include("derived.catalogs.people")
    body = File.read(File.join(root, "zones/derived/catalogs/people.md"))
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
    expect(File.binread(published)).to eq(File.binread(File.join(root, "zones/derived/catalogs/people.md")))
  end

  it "materializes a templateless JSON entry with _meta injected first" do
    Textus::Builder.new(store).build(prefix: "derived.people-json")
    raw = File.read(File.join(root, "zones/derived/people.json"))
    parsed = JSON.parse(raw)

    expect(parsed.keys.first).to eq("_meta")
    expect(parsed["_meta"].keys).to eq(%w[generated_at from])
    expect(parsed["_meta"]["from"]).to eq(["working.people"])
    expect(parsed["entries"]).to be_an(Array)
    expect(parsed["entries"].map { |r| r["name"] }).to contain_exactly("alice", "bob")
  end

  it "materializes a templateless YAML entry whose reducer shapes the body" do
    Textus::Builder.new(store).build(prefix: "derived.people-yaml")
    raw = File.read(File.join(root, "zones/derived/people.yaml"))
    parsed = YAML.safe_load(raw, aliases: false)

    expect(parsed.keys.first).to eq("_meta")
    expect(parsed["_meta"].keys).to eq(%w[generated_at from reduce])
    expect(parsed["_meta"]["reduce"]).to eq("envelope")
    expect(parsed["protocol"]).to eq("textus/2")
    expect(parsed["people"].map { |r| r["name"] }).to contain_exactly("alice", "bob")
  end

  it "supports the JSON template escape hatch and injects _meta first" do
    Textus::Builder.new(store).build(prefix: "derived.people-json-tpl")
    raw = File.read(File.join(root, "zones/derived/people-tpl.json"))
    parsed = JSON.parse(raw)

    expect(parsed.keys.first).to eq("_meta")
    expect(parsed["_meta"].keys).to eq(%w[generated_at from template])
    expect(parsed["_meta"]["template"]).to eq("people.json.mustache")
    expect(parsed["people"].map { |r| r["name"] }).to contain_exactly("alice", "bob")
  end

  it "raises bad_render when a JSON template renders invalid JSON" do
    expect { Textus::Builder.new(store).build(prefix: "derived.people-bad-tpl") }
      .to raise_error(Textus::BadRender) { |e| expect(e.code).to eq("bad_render") }
  end
end
