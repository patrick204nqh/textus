RSpec.describe Textus::Core::Freshness::Verdict do
  describe ".build" do
    it "defaults fetching to false and reason/fetch_error/checked_at/ttl_remaining_ms to nil" do
      v = described_class.build(stale: false)
      expect(v.stale).to be false
      expect(v.fetching).to be false
      expect(v.reason).to be_nil
      expect(v.fetch_error).to be_nil
    end

    it "accepts all fields" do
      v = described_class.build(stale: true, fetching: true, reason: "ttl exceeded",
                                fetch_error: "timeout", checked_at: Time.now, ttl_remaining_ms: 0)
      expect(v.stale).to be true
      expect(v.reason).to eq("ttl exceeded")
      expect(v.fetch_error).to eq("timeout")
    end
  end

  describe "#to_h_for_wire" do
    it "emits stale, stale_reason, and fetching" do
      wire = described_class.build(stale: true, reason: "ttl exceeded").to_h_for_wire
      expect(wire).to include("stale" => true, "stale_reason" => "ttl exceeded", "fetching" => false)
    end

    it "omits fetch_error when nil" do
      wire = described_class.build(stale: false).to_h_for_wire
      expect(wire).not_to have_key("fetch_error")
    end

    it "includes fetch_error when present" do
      wire = described_class.build(stale: false, fetch_error: "timeout").to_h_for_wire
      expect(wire["fetch_error"]).to eq("timeout")
    end

    it "does not emit gem-side fields checked_at or ttl_remaining_ms" do
      wire = described_class.build(stale: false, checked_at: Time.now, ttl_remaining_ms: 5000).to_h_for_wire
      expect(wire).not_to have_key("checked_at")
      expect(wire).not_to have_key("ttl_remaining_ms")
    end
  end
end
