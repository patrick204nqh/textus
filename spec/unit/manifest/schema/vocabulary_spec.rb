# frozen_string_literal: true

require "spec_helper"

RSpec.describe Textus::Manifest::Schema::Vocabulary do
  it "includes raw in LANE_KINDS" do
    expect(Textus::Manifest::Schema::LANE_KINDS).to include("raw")
  end

  it "maps raw kind to ingest capability" do
    expect(Textus::Manifest::Schema::KIND_REQUIRES_VERB["raw"]).to eq("ingest")
  end

  it "includes ingest in CAPABILITIES" do
    expect(Textus::Manifest::Schema::CAPABILITIES).to include("ingest")
  end

  it "maintains a bijection (all capabilities are unique)" do
    verbs = Textus::Manifest::Schema::LANES.values
    expect(verbs.uniq).to eq(verbs)
  end
end
