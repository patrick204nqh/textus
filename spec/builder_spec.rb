# rubocop:disable RSpec/MultipleDescribes
require "spec_helper"
require "fileutils"
require "json"
require "tmpdir"
require "yaml"

RSpec.describe Textus::Application::Writes::Build do
  include_context "textus_store_fixture"

  let(:store) { Textus::Store.new(root) }
  let(:build_use_case) do
    Textus::Operations.for(store, role: "builder").method(:build)
  end

  before do
    FileUtils.mkdir_p(File.join(root, "zones/working/people"))
    FileUtils.mkdir_p(File.join(root, "zones/output"))
    FileUtils.mkdir_p(File.join(root, "templates"))

    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: working, write_policy: [human, agent, runner] }
        - { name: output, write_policy: [builder] }
      entries:
        - { key: working.people, path: working/people, zone: working, schema: null, owner: o, nested: true }
        - key: output.catalogs.people
          path: output/catalogs/people.md
          zone: output
          schema: null
          owner: builder:auto
          compute: { kind: projection, select: working.people, pluck: [name, org], sort_by: name }
          template: people.mustache
          publish_to: [PEOPLE.md]
        - key: output.people-json
          path: output/people.json
          zone: output
          format: json
          schema: null
          owner: builder:auto
          compute: { kind: projection, select: working.people, pluck: [name, org], sort_by: name }
        - key: output.people-yaml
          path: output/people.yaml
          zone: output
          format: yaml
          schema: null
          owner: builder:auto
          compute: { kind: projection, select: working.people, pluck: [name, org], transform: envelope }
        - key: output.people-json-tpl
          path: output/people-tpl.json
          zone: output
          format: json
          schema: null
          owner: builder:auto
          compute: { kind: projection, select: working.people, pluck: [name, org], sort_by: name }
          template: people.json.mustache
        - key: output.people-bad-tpl
          path: output/people-bad.json
          zone: output
          format: json
          schema: null
          owner: builder:auto
          compute: { kind: projection, select: working.people, pluck: [name, org], sort_by: name }
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
    store.bus.register(:transform_rows, :envelope) do |store:, rows:, config:|
      _ = config
      _ = store
      { "protocol" => "textus/3", "people" => rows.sort_by { |r| r["name"].to_s } }
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
    expect(parsed["protocol"]).to eq("textus/3")
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

RSpec.describe "Builder :file_published events" do
  include_context "textus_store_fixture"

  let(:store) { Textus::Store.new(root) }

  before do
    FileUtils.mkdir_p(File.join(root, "zones/working"))
    FileUtils.mkdir_p(File.join(root, "zones/output"))
    FileUtils.mkdir_p(File.join(root, "zones/working/agents"))
    FileUtils.mkdir_p(File.join(root, "templates"))
  end

  describe "publish_to: fires :file_published once per target path" do
    before do
      File.write(File.join(root, "manifest.yaml"), <<~YAML)
        version: textus/3
        zones:
          - { name: working, write_policy: [human, agent, runner] }
          - { name: output, write_policy: [builder] }
        entries:
          - { key: working.note, path: working/note.md, zone: working, schema: null }
          - key: output.note
            path: output/note.md
            zone: output
            schema: null
            owner: builder:auto
            compute: { kind: projection, select: working.note }
            template: echo.mustache
            publish_to:
              - out/one.md
              - out/two.md
      YAML

      File.write(File.join(root, "templates/echo.mustache"), "hello {{key}}\n")
      File.write(File.join(root, "zones/working/note.md"),
                 "---\nkey: working.note\n---\nbody\n")
    end

    it "fires :file_published once per publish_to target with correct key/source/target" do
      captured = []
      store.bus.register(:file_published, :capture) do |key:, envelope:, source:, target:, **|
        _ = envelope
        captured << { key: key, source: source, target: target }
      end

      Textus::Operations.for(store, role: "builder").method(:build)
                        .call(prefix: "output.note")

      expect(captured.size).to eq(2)
      expect(captured.map { _1[:key] }).to all(eq("output.note"))

      targets = captured.map { _1[:target] }
      expect(targets).to include(File.join(tmp, "out/one.md"))
      expect(targets).to include(File.join(tmp, "out/two.md"))

      sources = captured.map { _1[:source] }
      expect(sources).to all(end_with("output/note.md"))
    end

    it "fires :build_completed exactly once per output entry regardless of publish_to count" do
      build_events = []
      store.bus.register(:build_completed, :capture_build) do |key:, envelope:, sources:, **|
        _ = envelope
        build_events << { key: key, sources: sources }
      end

      Textus::Operations.for(store, role: "builder").method(:build)
                        .call(prefix: "output.note")

      expect(build_events.size).to eq(1)
      expect(build_events.first[:key]).to eq("output.note")
    end
  end

  describe "publish_each: fires :file_published once per leaf" do
    before do
      File.write(File.join(root, "manifest.yaml"), <<~YAML)
        version: textus/3
        zones:
          - { name: working, write_policy: [human, agent, runner] }
        entries:
          - key: working.agents
            path: working/agents
            zone: working
            schema: null
            nested: true
            publish_each: "agents/{basename}.md"
      YAML

      File.write(File.join(root, "zones/working/agents/alpha.md"),
                 "---\nname: alpha\n---\nbody\n")
      File.write(File.join(root, "zones/working/agents/beta.md"),
                 "---\nname: beta\n---\nbody\n")
    end

    it "fires :file_published once per leaf with the correct leaf key and target" do
      captured = []
      store.bus.register(:file_published, :capture_leaf) do |key:, envelope:, source:, target:, **|
        _ = envelope
        captured << { key: key, source: source, target: target }
      end

      Textus::Operations.for(store, role: "builder").publish

      expect(captured.size).to eq(2)
      keys = captured.map { _1[:key] }
      expect(keys).to contain_exactly("working.agents.alpha", "working.agents.beta")

      targets = captured.map { _1[:target] }
      expect(targets).to include(File.join(tmp, "agents/alpha.md"))
      expect(targets).to include(File.join(tmp, "agents/beta.md"))
    end
  end
end

RSpec.describe "Textus::Builder::Pipeline idempotent writes" do
  include_context "textus_store_fixture"

  let(:store) { Textus::Store.new(root) }
  let(:build_use_case) { Textus::Operations.for(store, role: "builder").method(:build) }

  before do
    FileUtils.mkdir_p(File.join(root, "zones/working/people"))
    FileUtils.mkdir_p(File.join(root, "zones/output"))
    FileUtils.mkdir_p(File.join(root, "templates"))

    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: working, write_policy: [human, agent, runner] }
        - { name: output, write_policy: [builder] }
      entries:
        - { key: working.people, path: working/people, zone: working, schema: null, owner: o, nested: true }
        - key: output.catalog-md
          path: output/catalog.md
          zone: output
          schema: null
          owner: builder:auto
          compute: { kind: projection, select: working.people, pluck: [name], sort_by: name }
          template: people.mustache
        - key: output.catalog-json
          path: output/catalog.json
          zone: output
          format: json
          schema: null
          owner: builder:auto
          compute: { kind: projection, select: working.people, pluck: [name], sort_by: name }
        - key: output.catalog-yaml
          path: output/catalog.yaml
          zone: output
          format: yaml
          schema: null
          owner: builder:auto
          compute: { kind: projection, select: working.people, pluck: [name], sort_by: name, transform: envelope }
        - key: output.catalog-txt
          path: output/catalog.txt
          zone: output
          format: text
          schema: null
          owner: builder:auto
          compute: { kind: projection, select: working.people, pluck: [name], sort_by: name }
          template: people.mustache
    YAML

    File.write(File.join(root, "templates/people.mustache"), "{{#entries}}- {{name}}\n{{/entries}}")
    File.write(
      File.join(root, "zones/working/people/alice.md"),
      "---\nuid: u-alice\nname: alice\n---\n",
    )

    store.bus.register(:transform_rows, :envelope) do |store:, rows:, config:|
      _ = config
      _ = store
      { "protocol" => "textus/3", "people" => rows.sort_by { |r| r["name"].to_s } }
    end
  end

  it "markdown: skips write when only generated.at would differ" do
    build_use_case.call(prefix: "output.catalog-md")
    path = File.join(root, "zones/output/catalog.md")
    mtime_before = File.mtime(path)
    bytes_before = File.binread(path)

    sleep 1.1 # ensure Time.now.iso8601 would round to a later second
    build_use_case.call(prefix: "output.catalog-md")

    expect(File.mtime(path)).to eq(mtime_before)
    expect(File.binread(path)).to eq(bytes_before)
  end

  it "json: skips write when only _meta.generated_at would differ" do
    build_use_case.call(prefix: "output.catalog-json")
    path = File.join(root, "zones/output/catalog.json")
    mtime_before = File.mtime(path)
    bytes_before = File.binread(path)

    sleep 1.1
    build_use_case.call(prefix: "output.catalog-json")

    expect(File.mtime(path)).to eq(mtime_before)
    expect(File.binread(path)).to eq(bytes_before)
  end

  it "yaml: skips write when only _meta.generated_at would differ" do
    build_use_case.call(prefix: "output.catalog-yaml")
    path = File.join(root, "zones/output/catalog.yaml")
    mtime_before = File.mtime(path)
    bytes_before = File.binread(path)

    sleep 1.1
    build_use_case.call(prefix: "output.catalog-yaml")

    expect(File.mtime(path)).to eq(mtime_before)
    expect(File.binread(path)).to eq(bytes_before)
  end

  it "text: skips write when bytes are identical" do
    build_use_case.call(prefix: "output.catalog-txt")
    path = File.join(root, "zones/output/catalog.txt")
    mtime_before = File.mtime(path)
    bytes_before = File.binread(path)

    sleep 1.1
    build_use_case.call(prefix: "output.catalog-txt")

    expect(File.mtime(path)).to eq(mtime_before)
    expect(File.binread(path)).to eq(bytes_before)
  end

  it "markdown: writes when source data actually changed" do
    build_use_case.call(prefix: "output.catalog-md")
    path = File.join(root, "zones/output/catalog.md")
    bytes_before = File.binread(path)

    File.write(
      File.join(root, "zones/working/people/bob.md"),
      "---\nuid: u-bob\nname: bob\n---\n",
    )
    sleep 1.1
    build_use_case.call(prefix: "output.catalog-md")

    expect(File.binread(path)).not_to eq(bytes_before)
    expect(File.binread(path)).to include("- bob")
  end
end
# rubocop:enable RSpec/MultipleDescribes
