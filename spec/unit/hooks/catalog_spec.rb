# frozen_string_literal: true

require "spec_helper"

RSpec.describe Textus::Hooks::Catalog do
  it "defines non-empty, frozen pubsub and rpc tables" do
    expect(described_class::PUBSUB).to be_a(Hash)
    expect(described_class::RPC).to be_a(Hash)
    expect(described_class::PUBSUB).to be_frozen
    expect(described_class::RPC).to be_frozen
    expect(described_class::PUBSUB).not_to be_empty
    expect(described_class::RPC).not_to be_empty
  end

  it "keeps pubsub and rpc event names disjoint" do
    overlap = described_class::PUBSUB.keys & described_class::RPC.keys
    expect(overlap).to be_empty
  end

  it "lists the canonical textus/3 rpc events" do
    expect(described_class::RPC.keys).to contain_exactly(:resolve_handler, :transform_rows, :validate)
  end
end
