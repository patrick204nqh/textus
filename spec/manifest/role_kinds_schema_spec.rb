require "spec_helper"

RSpec.describe "Textus::Manifest::Schema role declarations" do
  def parse(yaml)
    Textus::Manifest.parse(yaml)
  end

  it "accepts a roles: block with name + kind" do
    yaml = <<~YAML
      version: textus/3
      roles:
        - { name: owner,    kind: accept_authority }
        - { name: compiler, kind: generator }
        - { name: proposer, kind: proposer }
        - { name: fetcher,  kind: runner }
      zones:
        - { name: identity, write_policy: [owner] }
      entries: []
    YAML
    expect { parse(yaml) }.not_to raise_error
  end

  it "rejects an unknown kind" do
    yaml = <<~YAML
      version: textus/3
      roles:
        - { name: weirdo, kind: jester }
      zones:
        - { name: identity, write_policy: [weirdo] }
      entries: []
    YAML
    expect { parse(yaml) }.to raise_error(Textus::BadManifest, /unknown role kind .*jester/)
  end

  it "rejects more than one accept_authority role" do
    yaml = <<~YAML
      version: textus/3
      roles:
        - { name: owner,     kind: accept_authority }
        - { name: co_owner,  kind: accept_authority }
      zones:
        - { name: identity, write_policy: [owner] }
      entries: []
    YAML
    expect { parse(yaml) }.to raise_error(Textus::BadManifest, /exactly one accept_authority/)
  end

  it "rejects unknown keys inside a role entry" do
    yaml = <<~YAML
      version: textus/3
      roles:
        - { name: owner, kind: accept_authority, color: blue }
      zones:
        - { name: identity, write_policy: [owner] }
      entries: []
    YAML
    expect { parse(yaml) }.to raise_error(Textus::BadManifest, /unknown key 'color'/)
  end

  it "still parses manifests with no roles: block (defaults apply)" do
    yaml = <<~YAML
      version: textus/3
      zones:
        - { name: identity, write_policy: [human] }
      entries: []
    YAML
    expect { parse(yaml) }.not_to raise_error
  end
end
