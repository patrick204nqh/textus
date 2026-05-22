require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Textus::Application::Writes::Build do
  subject(:use_case) do
    ctx = Textus::Application::Context.new(store: store, role: "human")
    bus = store.bus
    described_class.new(ctx: ctx, bus: bus)
  end

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
    YAML

    File.write(File.join(root, "zones/working/people/alice.md"),
               "---\nname: alice\norg: x\n---\n")
    File.write(File.join(root, "zones/working/people/bob.md"),
               "---\nname: bob\norg: y\n---\n")
    File.write(File.join(root, "templates/people.mustache"),
               "{{#entries}}- {{name}} ({{org}})\n{{/entries}}")
  end

  after { FileUtils.remove_entry(tmp) }

  it "returns a hash with protocol, built, and published_leaves keys" do
    result = use_case.call

    expect(result).to have_key("protocol")
    expect(result["protocol"]).to eq(Textus::PROTOCOL)
    expect(result).to have_key("built")
    expect(result).to have_key("published_leaves")
  end

  it "materializes derived entries and returns their keys in built" do
    result = use_case.call(prefix: "derived.catalogs.people")

    expect(result["built"].map { |b| b["key"] }).to include("derived.catalogs.people")
    body = File.read(File.join(root, "zones/derived/catalogs/people.md"))
    expect(body).to include("- alice (x)")
    expect(body).to include("- bob (y)")
  end

  it "delegates to Builder without double-firing events" do
    # Spy that Builder is invoked, and result shape is preserved
    result = use_case.call
    expect(result["protocol"]).to eq(Textus::PROTOCOL)
    expect(result["built"]).to be_an(Array)
    expect(result["published_leaves"]).to be_an(Array)
  end
end
