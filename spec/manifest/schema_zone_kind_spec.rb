require "spec_helper"

RSpec.describe "Textus::Manifest::Schema zone kind" do
  def parse(zones_yaml)
    raw = YAML.safe_load(<<~YAML, aliases: false)
      version: textus/3
      zones:
      #{zones_yaml}
      entries: []
    YAML
    Textus::Manifest::Schema.validate!(raw)
  end

  it "accepts a known kind" do
    expect { parse("  - { name: review, kind: queue, write_policy: [agent] }") }.not_to raise_error
  end

  it "accepts a zone with no kind (kind is optional)" do
    expect { parse("  - { name: working, write_policy: [human] }") }.not_to raise_error
  end

  it "rejects an unknown kind" do
    expect { parse("  - { name: review, kind: mailbox, write_policy: [agent] }") }
      .to raise_error(Textus::BadManifest, /unknown zone kind 'mailbox'.*origin, quarantine, queue, derived/m)
  end
end
