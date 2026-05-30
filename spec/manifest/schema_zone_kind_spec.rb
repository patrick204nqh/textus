require "spec_helper"

RSpec.describe "Textus::Manifest::Schema zone kind" do
  def parse(zones_yaml, roles_yaml = nil)
    raw = YAML.safe_load(<<~YAML, aliases: false)
      version: textus/3
      #{roles_yaml}
      zones:
      #{zones_yaml}
      entries: []
    YAML
    Textus::Manifest::Schema.validate!(raw)
  end

  it "accepts a known kind" do
    expect { parse("  - { name: review, kind: queue }") }.not_to raise_error
  end

  it "rejects a zone with no kind (kind is required)" do
    expect { parse("  - { name: working }") }
      .to raise_error(Textus::BadManifest, /zone 'working' at '\$\.zones\[0\]' must declare a kind/)
  end

  it "rejects an unknown kind" do
    expect { parse("  - { name: review, kind: mailbox }") }
      .to raise_error(Textus::BadManifest, /unknown zone kind 'mailbox'.*origin, quarantine, queue, derived/m)
  end

  it "rejects two queue zones" do
    expect do
      parse(<<~Z)
        - { name: review,  kind: queue }
        - { name: triage,  kind: queue }
      Z
    end.to raise_error(Textus::BadManifest, /at most one zone may declare kind: queue/)
  end

  it "rejects a derived zone when no declared role holds build" do
    roles = <<~ROLES
      roles:
        - { name: owner, can: [accept, propose] }
    ROLES
    expect { parse("  - { name: output, kind: derived }", roles) }
      .to raise_error(Textus::BadManifest, /needs a role with capability 'build'/)
  end

  it "accepts a derived zone when a declared role holds build" do
    roles = <<~ROLES
      roles:
        - { name: owner,    can: [accept, propose] }
        - { name: compiler, can: [build] }
    ROLES
    expect { parse("  - { name: output, kind: derived }", roles) }.not_to raise_error
  end
end
