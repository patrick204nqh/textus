require "spec_helper"

RSpec.describe "Textus::Manifest::Schema role + capability declarations" do
  def parse(yaml)
    Textus::Manifest.parse(yaml)
  end

  it "accepts a roles: block with name + can" do
    yaml = <<~YAML
      version: textus/3
      roles:
        - { name: human,      can: [author, propose] }
        - { name: agent,      can: [propose] }
        - { name: automation, can: [ingest, reconcile] }
      zones:
        - { name: identity, kind: canon }
      entries: []
    YAML
    expect { parse(yaml) }.not_to raise_error
  end

  it "rejects an unknown verb in can" do
    yaml = <<~YAML
      version: textus/3
      roles:
        - { name: human, can: [teleport] }
      zones:
        - { name: identity, kind: canon }
      entries: []
    YAML
    expect { parse(yaml) }.to raise_error(Textus::BadManifest, /unknown capability 'teleport'/)
  end

  # WS2 / ADR 0088: the quarantine capability was renamed fetch→ingest (breaking,
  # no shim). A pre-0.51 manifest still saying `can: [fetch]` is rejected like any
  # unknown capability, but with a pointed hint at the new name.
  it "rejects the retired 'fetch' capability with an ingest hint" do
    yaml = <<~YAML
      version: textus/3
      roles:
        - { name: automation, can: [fetch, reconcile] }
      zones:
        - { name: feeds, kind: quarantine }
      entries: []
    YAML
    expect { parse(yaml) }.to raise_error(
      Textus::BadManifest,
      /unknown capability 'fetch'.*renamed to 'ingest' \(ADR 0088\)/m,
    )
  end

  it "rejects more than one role holding author" do
    yaml = <<~YAML
      version: textus/3
      roles:
        - { name: human, can: [author] }
        - { name: agent, can: [author] }
      zones:
        - { name: identity, kind: canon }
      entries: []
    YAML
    expect { parse(yaml) }.to raise_error(Textus::BadManifest, /at most one is allowed/)
  end

  it "rejects unknown keys inside a role entry" do
    yaml = <<~YAML
      version: textus/3
      roles:
        - { name: human, can: [author], color: blue }
      zones:
        - { name: identity, kind: canon }
      entries: []
    YAML
    expect { parse(yaml) }.to raise_error(Textus::BadManifest, /unknown key 'color'/)
  end

  it "rejects a role name outside the closed set {human, agent, automation}" do
    yaml = <<~YAML
      version: textus/3
      roles:
        - { name: importer, can: [ingest] }
      zones:
        - { name: feeds, kind: quarantine }
      entries: []
    YAML
    expect { Textus::Manifest::Data.parse(YAML.safe_load(yaml, aliases: false), root: ".") }
      .to raise_error(Textus::BadManifest, /unknown role name 'importer'/)
  end

  it "still parses manifests with no roles: block (defaults apply)" do
    yaml = <<~YAML
      version: textus/3
      zones:
        - { name: identity, kind: canon }
      entries: []
    YAML
    expect { parse(yaml) }.not_to raise_error
  end
end
