require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe "inject_intro:" do
  let(:tmp)  { Dir.mktmpdir }
  let(:root) { File.join(tmp, ".textus") }

  before do
    FileUtils.mkdir_p(File.join(root, "zones/canon"))
    FileUtils.mkdir_p(File.join(root, "zones/derived"))
    FileUtils.mkdir_p(File.join(root, "templates"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/1
      zones:
        - { name: canon,   writable_by: [human] }
        - { name: derived, writable_by: [build] }
      entries:
        - { key: canon.id, path: canon/id.md, zone: canon, schema: null }
        - key: derived.root
          path: derived/root.md
          zone: derived
          projection: { select: [canon.id], pluck: "*" }
          template: root.mustache
          inject_intro: true
    YAML
    File.write(File.join(root, "templates/root.mustache"), <<~TPL)
      protocol={{intro.protocol}}
      {{#intro.zones}}zone:{{name}}/{{purpose}}
      {{/intro.zones}}
    TPL
    File.write(File.join(root, "zones/canon/id.md"), "---\nname: id\n---\nx\n")
  end

  after { FileUtils.remove_entry(tmp) }

  it "injects intro: into template data when the flag is true" do
    store = Textus::Store.new(root)
    Textus::Builder.new(store).build
    body = File.read(File.join(root, "zones/derived/root.md"))
    expect(body).to include("protocol=textus/1")
    expect(body).to include("zone:canon/")
    expect(body).to include("zone:derived/")
  end

  it "raises on inject_intro: on a non-derived entry" do
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/1
      zones:
        - { name: canon, writable_by: [human] }
      entries:
        - key: canon.bad
          path: canon/bad.md
          zone: canon
          schema: null
          template: root.mustache
          inject_intro: true
    YAML
    expect { Textus::Store.new(root) }.to raise_error(Textus::UsageError, /inject_intro.*derived/)
  end

  it "raises on inject_intro: when no template is declared" do
    # JSON derived entries do not require a template (template is an escape
    # hatch). inject_intro: on a templateless derived entry must still raise.
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/1
      zones:
        - { name: canon,   writable_by: [human] }
        - { name: derived, writable_by: [build] }
      entries:
        - { key: canon.id, path: canon/id.md, zone: canon, schema: null }
        - key: derived.root
          path: derived/root.json
          zone: derived
          format: json
          projection: { select: [canon.id], pluck: "*" }
          inject_intro: true
    YAML
    expect { Textus::Store.new(root) }.to raise_error(Textus::UsageError, /inject_intro.*template/)
  end

  it "does not inject intro: when flag is absent" do
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/1
      zones:
        - { name: canon,   writable_by: [human] }
        - { name: derived, writable_by: [build] }
      entries:
        - { key: canon.id, path: canon/id.md, zone: canon, schema: null }
        - key: derived.root
          path: derived/root.md
          zone: derived
          projection: { select: [canon.id], pluck: "*" }
          template: root.mustache
    YAML
    store = Textus::Store.new(root)
    Textus::Builder.new(store).build
    body = File.read(File.join(root, "zones/derived/root.md"))
    expect(body).not_to include("protocol=textus/1")
  end
end
