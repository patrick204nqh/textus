require "spec_helper"

RSpec.describe Textus::Manifest::Rules do
  def rules_for(yaml, key)
    blocks = YAML.safe_load(yaml)["rules"]
    described_class.parse(blocks).for(key)
  end

  it "parses a lifecycle slot into a Policy::Lifecycle" do
    set = rules_for(<<~YAML, "feeds.cal")
      rules:
        - match: "feeds.*"
          lifecycle: { ttl: 1h, on_expire: refresh }
    YAML
    expect(set.lifecycle).to be_a(Textus::Domain::Policy::Lifecycle)
    expect(set.lifecycle.on_expire).to eq(:refresh)
    expect(set.lifecycle.ttl_seconds).to eq(3600)
  end

  it "resolves lifecycle per-slot, most-specific wins" do
    set = rules_for(<<~YAML, "review.oncall")
      rules:
        - match: "**"
          lifecycle: { ttl: 90d, on_expire: archive }
        - match: "review.*"
          lifecycle: { ttl: 30d, on_expire: drop }
    YAML
    expect(set.lifecycle.on_expire).to eq(:drop)
  end

  it "leaves lifecycle nil when no block declares it" do
    set = rules_for(<<~YAML, "x.y")
      rules:
        - match: "x.*"
          retention: { expire_after: 30d }
    YAML
    expect(set.lifecycle).to be_nil
  end
end
