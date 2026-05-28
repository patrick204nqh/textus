require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Textus::Application::Reads::Published do
  def build_store(root)
    textus = File.join(root, ".textus")
    FileUtils.mkdir_p(File.join(textus, "zones", "working", "people"))
    FileUtils.mkdir_p(File.join(textus, "zones", "output"))
    File.write(File.join(textus, "manifest.yaml"), <<~YAML)
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
          compute: { kind: projection, select: working.people }
          template: people.mustache
          publish_to: [PEOPLE.md]
    YAML
    FileUtils.mkdir_p(File.join(textus, "templates"))
    File.write(File.join(textus, "templates", "people.mustache"), "{{#entries}}- {{name}}\n{{/entries}}")
    File.write(File.join(textus, "zones", "working", "people", "alice.md"), "---\nname: alice\n---\n")
    Textus::Store.new(textus)
  end

  it "returns entries that have publish_to, including output.catalogs.people" do
    Dir.mktmpdir do |root|
      store = build_store(root)
      ops = store.session(role: "human")
      result = ops.published
      expect(result.map { |r| r["key"] }).to include("output.catalogs.people")
    end
  end
end
