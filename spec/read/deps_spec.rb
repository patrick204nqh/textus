require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Textus::Read::Deps do
  def build_store(root)
    textus = File.join(root, ".textus")
    FileUtils.mkdir_p(File.join(textus, "zones", "working", "people"))
    FileUtils.mkdir_p(File.join(textus, "zones", "output"))
    File.write(File.join(textus, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: working, kind: canon }
        - { name: output, kind: derived }
      entries:
        - { key: working.people, path: working/people, zone: working, schema: null, owner: o, nested: true, kind: nested}

        - key: output.catalogs.people
          kind: derived
          path: output/catalogs/people.md
          zone: output
          schema: null
          owner: automation:auto
          compute: { kind: projection, select: working.people }
          template: people.mustache
    YAML
    FileUtils.mkdir_p(File.join(textus, "templates"))
    File.write(File.join(textus, "templates", "people.mustache"), "{{#entries}}- {{name}}\n{{/entries}}")
    File.write(File.join(textus, "zones", "working", "people", "alice.md"), "---\nname: alice\n---\n")
    Textus::Store.new(textus)
  end

  it "returns the keys that output.catalogs.people depends on" do
    Dir.mktmpdir do |root|
      store = build_store(root)
      ops = store.as("human")
      result = ops.deps("output.catalogs.people")
      expect(result).to include("working.people")
    end
  end
end
