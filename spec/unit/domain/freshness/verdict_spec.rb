require "spec_helper"

RSpec.describe Textus::Domain::Freshness::Verdict do
  it "builds a fresh verdict with wire keys" do
    v = described_class.build(stale: false)
    expect(v.to_h_for_wire).to eq("stale" => false, "stale_reason" => nil, "fetching" => false)
  end

  it "carries a stale reason and a fetch_error onto the wire" do
    v = described_class.build(stale: true, reason: "ttl exceeded", fetch_error: "boom")
    expect(v.to_h_for_wire).to eq(
      "stale" => true, "stale_reason" => "ttl exceeded", "fetching" => false, "fetch_error" => "boom",
    )
  end
end
