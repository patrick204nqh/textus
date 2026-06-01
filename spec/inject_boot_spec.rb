require "spec_helper"

RSpec.describe "inject_boot:" do
  include_context "textus_store_fixture"

  before do
    FileUtils.mkdir_p(File.join(root, "zones/identity"))
    FileUtils.mkdir_p(File.join(root, "zones/artifacts"))
    FileUtils.mkdir_p(File.join(root, "templates"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: identity, kind: canon }
        - { name: artifacts,   kind: derived }
      entries:
        - { key: identity.id, path: identity/id.md, zone: identity, kind: leaf}

        - key: artifacts.root
          kind: derived
          path: artifacts/root.md
          zone: artifacts
          compute: { kind: projection, select: [identity.id], pluck: "*" }
          template: root.mustache
          inject_boot: true
    YAML
    File.write(File.join(root, "templates/root.mustache"), <<~TPL)
      protocol={{boot.protocol}}
      {{#boot.zones}}zone:{{name}}/{{purpose}}
      {{/boot.zones}}
    TPL
    File.write(File.join(root, "zones/identity/id.md"), "---\nname: id\n---\nx\n")
  end

  it "injects boot: into template data when the flag is true" do
    store = Textus::Store.new(root)
    store.as("automation").publish
    body = File.read(File.join(root, "zones/artifacts/root.md"))
    expect(body).to include("protocol=textus/3")
    expect(body).to include("zone:identity/")
    expect(body).to include("zone:artifacts/")
  end

  it "raises on inject_boot: on a non-derived entry" do
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: identity, kind: canon }
      entries:
        - key: identity.bad
          kind: derived
          path: identity/bad.md
          zone: identity
          template: root.mustache
          compute: { kind: projection }
          inject_boot: true
    YAML
    expect { Textus::Store.new(root) }.to raise_error(Textus::UsageError, /inject_boot.*derived/)
  end

  it "raises on inject_boot: when no template is declared" do
    # JSON derived entries do not require a template (template is an escape
    # hatch). inject_boot: on a templateless derived entry must still raise.
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: identity, kind: canon }
        - { name: artifacts,   kind: derived }
      entries:
        - { key: identity.id, path: identity/id.md, zone: identity, kind: leaf}

        - key: artifacts.root
          kind: derived
          path: artifacts/root.json
          zone: artifacts
          format: json
          compute: { kind: projection, select: [identity.id], pluck: "*" }
          inject_boot: true
    YAML
    expect { Textus::Store.new(root) }.to raise_error(Textus::UsageError, /inject_boot.*template/)
  end

  it "does not inject boot: when flag is absent" do
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: identity, kind: canon }
        - { name: artifacts,   kind: derived }
      entries:
        - { key: identity.id, path: identity/id.md, zone: identity, kind: leaf}

        - key: artifacts.root
          kind: derived
          path: artifacts/root.md
          zone: artifacts
          compute: { kind: projection, select: [identity.id], pluck: "*" }
          template: root.mustache
    YAML
    store = Textus::Store.new(root)
    store.as("automation").publish
    body = File.read(File.join(root, "zones/artifacts/root.md"))
    expect(body).not_to include("protocol=textus/3")
  end
end
