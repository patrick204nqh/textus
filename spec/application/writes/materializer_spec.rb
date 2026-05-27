require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Textus::Application::Writes::Materializer do
  subject(:materializer) do
    Textus::Application::Writes::Materializer.new(
      ctx: ctx,
      manifest: store.manifest,
      file_store: store.file_store,
      bus: store.bus,
      root: root,
      store: store,
    )
  end

  include_context "textus_store_fixture"

  let(:store) { Textus::Store.new(root) }
  let(:ctx)   { test_ctx(role: "builder") }

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
        - { key: working.people, path: working/people, zone: working, schema: null, owner: o, nested: true, kind: nested }

        - key: output.catalogs.people
          kind: derived
          path: output/catalogs/people.md
          zone: output
          schema: null
          owner: builder:auto
          compute: { kind: projection, select: working.people, pluck: [name, org], sort_by: name }
          template: people.mustache
    YAML

    File.write(File.join(root, "zones/working/people/alice.md"),
               "---\nname: alice\norg: x\n---\n")
    File.write(File.join(root, "zones/working/people/bob.md"),
               "---\nname: bob\norg: y\n---\n")
    File.write(File.join(root, "templates/people.mustache"),
               "{{#entries}}- {{name}} ({{org}})\n{{/entries}}")
  end

  it "materializes a Derived entry and writes rendered content to disk" do
    mentry = store.manifest.entries.find { |e| e.key == "output.catalogs.people" }
    expect(mentry).to be_a(Textus::Manifest::Entry::Derived)

    target_path = materializer.run(mentry)

    expect(File.exist?(target_path)).to be true
    content = File.read(target_path)
    expect(content).to include("- alice (x)")
    expect(content).to include("- bob (y)")
  end
end
