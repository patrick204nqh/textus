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
        - { name: automation, can: [reconcile] }
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

  # ADR 0090: the quarantine capability folded into reconcile. A manifest still
  # naming the old quarantine capability (`ingest`, or legacy `fetch`) is rejected
  # with a pointed hint at reconcile.
  it "rejects the folded quarantine capability with a reconcile hint" do
    %w[ingest fetch].each do |old|
      yaml = <<~YAML
        version: textus/3
        roles:
          - { name: automation, can: [#{old}, reconcile] }
        zones:
          - { name: feeds, kind: quarantine }
        entries: []
      YAML
      expect { parse(yaml) }.to raise_error(
        Textus::BadManifest,
        /unknown capability '#{old}'.*folded into 'reconcile' \(ADR 0090\)/m,
      )
    end
  end

  it "rejects retired lifecycle:/materialize: rule fields with an upkeep hint" do
    %w[lifecycle materialize].each do |old|
      yaml = <<~YAML
        version: textus/3
        zones: [{ name: knowledge, kind: canon }]
        entries: [{ key: knowledge.x, path: knowledge/x.md, zone: knowledge, kind: leaf }]
        rules:
          - { match: knowledge.x, #{old}: {} }
      YAML
      expect { parse(yaml) }.to raise_error(Textus::BadManifest, /#{old}.*merged into `upkeep`.*ADR 0090/m)
    end
  end

  # ADR 0090: `on:` is upkeep's discriminator. A BARE `on:` parses as the
  # YAML 1.1 boolean true (Psych), so an unquoted `upkeep: { on: stale }`
  # becomes `{ true => "stale" }`. Catch this footgun at load with a quoting
  # hint instead of the generic "unknown key 'true'".
  it "rejects an unquoted on: in upkeep with a quoting hint" do
    yaml = <<~YAML
      version: textus/3
      zones: [{ name: knowledge, kind: canon }]
      entries: [{ key: knowledge.x, path: knowledge/x.md, zone: knowledge, kind: leaf }]
      rules:
        - { match: knowledge.x, upkeep: { on: stale, ttl: 6h, action: refresh } }
    YAML
    expect { parse(yaml) }.to raise_error(
      Textus::BadManifest,
      /upkeep.*"on".*quote|quote.*on/i,
    )
    expect { parse(yaml) }.to raise_error(Textus::BadManifest, /boolean/i)
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
