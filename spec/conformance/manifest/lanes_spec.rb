require "spec_helper"

RSpec.describe "Schema::LANES single source of truth (ADR 0034)" do
  let(:s) { Textus::Manifest::Schema }

  it "is the kind => required-capability function (ADR 0091: quarantine + derived folded into machine; ADR 0114: raw→ingest)" do
    expect(s::LANES).to eq(
      "canon"     => "author",
      "workspace" => "keep",
      "machine"   => "converge",
      "queue"     => "propose",
      "raw"       => "ingest",
    )
  end

  it "derives LANE_KINDS from the lane keys (order preserved for the error message)" do
    expect(s::LANE_KINDS).to eq(%w[canon workspace machine queue raw])
  end

  it "derives CAPABILITIES from the lane values, de-duplicated (five: machine requires converge, raw→ingest)" do
    expect(s::CAPABILITIES).to contain_exactly("author", "keep", "propose", "converge", "ingest")
  end

  it "derives KIND_REQUIRES_VERB as the lane table itself" do
    expect(s::KIND_REQUIRES_VERB).to eq(s::LANES)
    expect(s::LANE_KINDS.map { |k| s::KIND_REQUIRES_VERB.fetch(k) })
      .to eq(s::LANE_KINDS.map { |k| s::LANES.fetch(k) })
  end

  it "keeps the lane table and its derivations frozen" do
    expect(s::LANES).to be_frozen
    expect(s::LANE_KINDS).to be_frozen
    expect(s::CAPABILITIES).to be_frozen
  end
end
