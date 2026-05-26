# frozen_string_literal: true

require "spec_helper"

RSpec.describe Textus::Hooks::FireReport do
  it "is ok when nothing errored or timed out" do
    r = described_class.new(fired: %i[a b], errored: [], timed_out: [])
    expect(r.ok?).to be(true)
    expect(r.failures).to eq([])
  end

  it "is not ok when any hook errored" do
    r = described_class.new(fired: [:a], errored: [:b], timed_out: [])
    expect(r.ok?).to be(false)
    expect(r.failures).to eq([:b])
  end

  it "is not ok when any hook timed out" do
    r = described_class.new(fired: [:a], errored: [], timed_out: [:c])
    expect(r.ok?).to be(false)
    expect(r.failures).to eq([:c])
  end

  it "lists errored + timed_out together in failures" do
    r = described_class.new(fired: [:a], errored: [:b], timed_out: [:c])
    expect(r.failures).to contain_exactly(:b, :c)
  end

  it "is frozen" do
    r = described_class.new(fired: [], errored: [], timed_out: [])
    expect(r).to be_frozen
  end
end
