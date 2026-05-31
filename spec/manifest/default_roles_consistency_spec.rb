require "spec_helper"

RSpec.describe "default role vocabulary: fallback stays consistent with the scaffold (ADR 0034 / D3)" do
  # Two DISTINCT defaults that must stay RELATED, not equal:
  #   Capabilities::DEFAULT_MAPPING — fallback when a manifest omits roles:
  #   Init::DEFAULT_MANIFEST        — what `textus init` writes (always has roles:)
  # capabilities.rb documents the fallback as intentionally NARROWER (agent is
  # propose-only vs the scaffold's propose+keep). Guard the relationship, not equality.
  let(:scaffold) do
    YAML.safe_load(Textus::Init::DEFAULT_MANIFEST, aliases: false)["roles"]
        .to_h { |r| [r["name"], r["can"]] }
  end
  let(:fallback) { Textus::Manifest::Capabilities::DEFAULT_MAPPING }

  it "defines the same role names in both defaults" do
    expect(scaffold.keys).to match_array(fallback.keys)
  end

  it "never lets a fallback role grant more than the scaffold grants it" do
    fallback.each do |role, caps|
      surplus = caps - scaffold.fetch(role)
      expect(surplus).to eq([]),
                         "fallback role #{role.inspect} has #{caps.inspect}, exceeding scaffold #{scaffold[role].inspect}"
    end
  end
end
