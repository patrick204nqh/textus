require "spec_helper"

RSpec.describe "Textus::Manifest::Schema zone kind" do
  def parse(zones_yaml, roles_yaml = nil)
    raw = YAML.safe_load(<<~YAML, aliases: false)
      version: textus/3
      #{roles_yaml}
      lanes:
      #{zones_yaml}
      entries: []
    YAML
    Textus::Manifest::Schema.validate!(raw)
  end

  it "accepts a known kind" do
    expect { parse("  - { name: review, kind: queue }") }.not_to raise_error
  end

  it "rejects a lane with no kind (kind is required)" do
    expect { parse("  - { name: knowledge }") }
      .to raise_error(Textus::BadManifest, /must declare a kind|is missing/)
  end

  it "rejects an unknown kind" do
    expect { parse("  - { name: review, kind: mailbox }") }
      .to raise_error(Textus::BadManifest, /unknown lane kind 'mailbox'|must be one of/)
  end

  it "rejects two queue lanes" do
    expect do
      parse(<<~Z)
        - { name: review,  kind: queue }
        - { name: triage,  kind: queue }
      Z
    end.to raise_error(Textus::BadManifest, /at most one lane may declare kind: queue/)
  end

  it "rejects a machine lane when no declared role holds converge" do
    roles = <<~ROLES
      roles:
        - { name: human, can: [author, propose] }
    ROLES
    expect { parse("  - { name: artifacts, kind: machine }", roles) }
      .to raise_error(Textus::BadManifest, /needs a role with capability 'converge'/)
  end

  it "accepts a machine lane when a declared role holds converge" do
    roles = <<~ROLES
      roles:
        - { name: human,      can: [author, propose] }
        - { name: automation, can: [converge] }
    ROLES
    expect { parse("  - { name: artifacts, kind: machine }", roles) }.not_to raise_error
  end
end
