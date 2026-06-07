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
        - { name: artifacts,   kind: machine }
      entries:
        - { key: identity.id, path: identity/id.md, zone: identity, kind: leaf}

        - key: artifacts.root
          kind: derived
          path: artifacts/root.md
          zone: artifacts
          source: { from: template, template: root.mustache, inject_boot: true, project: { select: [identity.id], pluck: "*" } }
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
    store.as("automation").reconcile
    body = File.read(File.join(root, "zones/artifacts/root.md"))
    expect(body).to include("protocol=textus/3")
    expect(body).to include("zone:identity/")
    expect(body).to include("zone:artifacts/")
  end

  it "is a source-only concern: a leaf entry has no inject_boot and loads cleanly" do
    # ADR 0093: inject_boot: lives under source: (derived only). A leaf has no
    # source, so inject_boot never applies and the manifest loads cleanly.
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: identity, kind: canon }
      entries:
        - key: identity.ok
          kind: leaf
          path: identity/ok.md
          zone: identity
    YAML
    store = Textus::Store.new(root)
    entry = store.container.manifest.data.entries.find { |e| e.key == "identity.ok" }
    expect(entry.inject_boot).to be(false)
  end

  it "raises on inject_boot: when no template is declared" do
    # JSON derived entries do not require a template (template is an escape
    # hatch). inject_boot: on a templateless derived entry must still raise.
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: identity, kind: canon }
        - { name: artifacts,   kind: machine }
      entries:
        - { key: identity.id, path: identity/id.md, zone: identity, kind: leaf}

        - key: artifacts.root
          kind: derived
          path: artifacts/root.json
          zone: artifacts
          format: json
          source: { from: template, inject_boot: true, project: { select: [identity.id], pluck: "*" } }
    YAML
    expect { Textus::Store.new(root) }.to raise_error(Textus::UsageError, /inject_boot.*template/)
  end

  it "does not inject boot: when flag is absent" do
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: identity, kind: canon }
        - { name: artifacts,   kind: machine }
      entries:
        - { key: identity.id, path: identity/id.md, zone: identity, kind: leaf}

        - key: artifacts.root
          kind: derived
          path: artifacts/root.md
          zone: artifacts
          source: { from: template, template: root.mustache, project: { select: [identity.id], pluck: "*" } }
    YAML
    store = Textus::Store.new(root)
    store.as("automation").reconcile
    body = File.read(File.join(root, "zones/artifacts/root.md"))
    expect(body).not_to include("protocol=textus/3")
  end
end
