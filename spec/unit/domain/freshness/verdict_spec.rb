require "spec_helper"

RSpec.describe Textus::Core::Freshness::Verdict do
  describe ".build / .new" do
    it "constructs with defaults via .build" do
      v = described_class.build(stale: false)
      aggregate_failures do
        expect(v.stale).to be(false)
        expect(v.fetching).to be(false)
        expect(v.reason).to be_nil
        expect(v.fetch_error).to be_nil
        expect(v.checked_at).to be_nil
        expect(v.ttl_remaining_ms).to be_nil
      end
    end

    it "constructs with all fields" do
      ts = Time.utc(2026, 5, 26)
      v = described_class.build(
        stale: true, fetching: true, reason: "ttl exceeded",
        fetch_error: "boom", checked_at: ts, ttl_remaining_ms: 42
      )
      aggregate_failures do
        expect(v.stale).to be(true)
        expect(v.fetching).to be(true)
        expect(v.reason).to eq("ttl exceeded")
        expect(v.fetch_error).to eq("boom")
        expect(v.checked_at).to eq(ts)
        expect(v.ttl_remaining_ms).to eq(42)
      end
    end
  end

  describe "equality" do
    it "two values with the same fields are equal" do
      a = described_class.build(stale: true, reason: "x")
      b = described_class.build(stale: true, reason: "x")
      expect(a).to eq(b)
      expect(a.hash).to eq(b.hash)
    end

    it "two values with different fields are not equal" do
      a = described_class.build(stale: true, reason: "x")
      b = described_class.build(stale: true, reason: "y")
      expect(a).not_to eq(b)
    end
  end

  describe "#to_h_for_wire" do
    it "emits legacy keys 'stale', 'stale_reason', 'fetching'" do
      v = described_class.build(stale: true, reason: "ttl exceeded", fetching: false)
      expect(v.to_h_for_wire).to eq(
        "stale" => true,
        "stale_reason" => "ttl exceeded",
        "fetching" => false,
      )
    end

    it "includes 'fetch_error' only when non-nil" do
      v = described_class.build(stale: true, fetch_error: "boom")
      expect(v.to_h_for_wire).to include("fetch_error" => "boom")
    end

    it "omits 'fetch_error' when nil (byte-compat with prior wire shape)" do
      v = described_class.build(stale: false)
      expect(v.to_h_for_wire).not_to have_key("fetch_error")
    end

    it "does NOT emit gem-side-only fields (checked_at, ttl_remaining_ms)" do
      v = described_class.build(
        stale: false, checked_at: Time.utc(2026, 1, 1), ttl_remaining_ms: 1234,
      )
      h = v.to_h_for_wire
      aggregate_failures do
        expect(h).not_to have_key("checked_at")
        expect(h).not_to have_key("ttl_remaining_ms")
      end
    end

    it "round-trips the legacy keys exactly (string keys, nil reason ok)" do
      v = described_class.build(stale: false, reason: nil, fetching: false)
      h = v.to_h_for_wire
      aggregate_failures do
        expect(h.keys).to all(be_a(String))
        expect(h["stale"]).to be(false)
        expect(h["stale_reason"]).to be_nil
        expect(h["fetching"]).to be(false)
      end
    end
  end

  describe "immutable update" do
    it "supports #with for non-destructive update" do
      v = described_class.build(stale: true, fetching: false)
      v2 = v.with(fetching: true)
      aggregate_failures do
        expect(v.fetching).to be(false)
        expect(v2.fetching).to be(true)
        expect(v2.stale).to be(true)
      end
    end
  end
end
