require "spec_helper"

RSpec.describe "Textus::Manifest::Schema role + capability declarations" do
  def parse(yaml)
    Textus::Manifest.parse(yaml)
  end

  it "accepts a roles: block with name + can" do
    yaml = <<~YAML
      version: textus/3
      roles:
        - { name: owner,    can: [author, propose] }
        - { name: compiler, can: [build] }
        - { name: proposer, can: [propose] }
        - { name: fetcher,  can: [fetch] }
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
        - { name: weirdo, can: [teleport] }
      zones:
        - { name: identity, kind: canon }
      entries: []
    YAML
    expect { parse(yaml) }.to raise_error(Textus::BadManifest, /unknown capability 'teleport'/)
  end

  it "rejects more than one role holding author" do
    yaml = <<~YAML
      version: textus/3
      roles:
        - { name: owner,    can: [author] }
        - { name: co_owner, can: [author] }
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
        - { name: owner, can: [author], color: blue }
      zones:
        - { name: identity, kind: canon }
      entries: []
    YAML
    expect { parse(yaml) }.to raise_error(Textus::BadManifest, /unknown key 'color'/)
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
