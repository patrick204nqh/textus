require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Textus::Application::Writes::Build do
  subject(:use_case) do
    ctx = test_ctx(role: "human")
    store.bus
    build_build(store, ctx)
  end

  include_context "textus_store_fixture"

  let(:store) { Textus::Store.new(root) }

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
        - { key: working.people, path: working/people, zone: working, schema: null, owner: o, nested: true, kind: nested}

        - key: output.catalogs.people
          kind: derived
          path: output/catalogs/people.md
          zone: output
          schema: null
          owner: builder:auto
          compute: { kind: projection, select: working.people, pluck: [name, org], sort_by: name }
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

  it "returns a hash with protocol and built keys" do
    result = use_case.call

    expect(result).to have_key("protocol")
    expect(result["protocol"]).to eq(Textus::PROTOCOL)
    expect(result).to have_key("built")
    expect(result).not_to have_key("published_leaves")
  end

  it "materializes output entries and returns their keys in built" do
    result = use_case.call(prefix: "output.catalogs.people")

    expect(result["built"].map { |b| b["key"] }).to include("output.catalogs.people")
    body = File.read(File.join(root, "zones/output/catalogs/people.md"))
    expect(body).to include("- alice (x)")
    expect(body).to include("- bob (y)")
  end

  it "fires :build_completed exactly once per output entry with correlation_id" do
    captured = []
    store.bus.register(:build_completed, :capture) do |ctx:, key:, **|
      captured << { key: key, correlation_id: ctx.correlation_id }
    end

    ctx = test_ctx(role: "builder", correlation_id: "cid-test-123")
    build_build(store, ctx).call

    expect(captured.size).to eq(1)
    expect(captured.first[:key]).to eq("output.catalogs.people")
    expect(captured.first[:correlation_id]).to eq("cid-test-123")
  end

  it "fires :file_published with correlation_id for each publish_to target" do
    captured = []
    store.bus.register(:file_published, :capture) do |ctx:, key:, target:, **|
      captured << { key: key, correlation_id: ctx.correlation_id, target: target }
    end

    ctx = test_ctx(role: "builder", correlation_id: "cid-pub-456")
    build_build(store, ctx).call

    expect(captured).not_to be_empty
    expect(captured.map { _1[:correlation_id] }).to all(eq("cid-pub-456"))
  end
end
