require "spec_helper"

RSpec.describe "Schema::LANES single source of truth (ADR 0034)" do
  let(:s) { Textus::Manifest::Schema }

  it "is the kind => required-capability function (ADR 0090: quarantine + derived share reconcile)" do
    expect(s::LANES).to eq(
      "canon" => "author", "workspace" => "keep", "quarantine" => "reconcile",
      "queue" => "propose", "derived" => "reconcile"
    )
  end

  it "derives ZONE_KINDS from the lane keys (order preserved for the error message)" do
    expect(s::ZONE_KINDS).to eq(%w[canon workspace quarantine queue derived])
  end

  it "derives CAPABILITIES from the lane values, de-duplicated (four: reconcile is shared)" do
    expect(s::CAPABILITIES).to contain_exactly("author", "keep", "propose", "reconcile")
  end

  it "derives KIND_REQUIRES_VERB as the lane table itself" do
    expect(s::KIND_REQUIRES_VERB).to eq(s::LANES)
    expect(s::ZONE_KINDS.map { |k| s::KIND_REQUIRES_VERB.fetch(k) })
      .to eq(s::ZONE_KINDS.map { |k| s::LANES.fetch(k) })
  end

  it "keeps the lane table and its derivations frozen" do
    expect(s::LANES).to be_frozen
    expect(s::ZONE_KINDS).to be_frozen
    expect(s::CAPABILITIES).to be_frozen
  end
end
