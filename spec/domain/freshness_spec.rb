require "spec_helper"

RSpec.describe Textus::Domain::Freshness do
  describe ".build / .new" do
    it "constructs with defaults via .build" do
      f = described_class.build(stale: false)
      aggregate_failures do
        expect(f.stale).to be(false)
        expect(f.refreshing).to be(false)
        expect(f.reason).to be_nil
        expect(f.refresh_error).to be_nil
        expect(f.checked_at).to be_nil
        expect(f.ttl_remaining_ms).to be_nil
      end
    end

    it "constructs with all fields" do
      ts = Time.utc(2026, 5, 26)
      f = described_class.build(
        stale: true, refreshing: true, reason: "ttl exceeded",
        refresh_error: "boom", checked_at: ts, ttl_remaining_ms: 42
      )
      aggregate_failures do
        expect(f.stale).to be(true)
        expect(f.refreshing).to be(true)
        expect(f.reason).to eq("ttl exceeded")
        expect(f.refresh_error).to eq("boom")
        expect(f.checked_at).to eq(ts)
        expect(f.ttl_remaining_ms).to eq(42)
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
    it "emits legacy keys 'stale', 'stale_reason', 'refreshing'" do
      f = described_class.build(stale: true, reason: "ttl exceeded", refreshing: false)
      expect(f.to_h_for_wire).to eq(
        "stale" => true,
        "stale_reason" => "ttl exceeded",
        "refreshing" => false,
      )
    end

    it "includes 'refresh_error' only when non-nil" do
      f = described_class.build(stale: true, refresh_error: "boom")
      expect(f.to_h_for_wire).to include("refresh_error" => "boom")
    end

    it "omits 'refresh_error' when nil (byte-compat with prior wire shape)" do
      f = described_class.build(stale: false)
      expect(f.to_h_for_wire).not_to have_key("refresh_error")
    end

    it "does NOT emit gem-side-only fields (checked_at, ttl_remaining_ms)" do
      f = described_class.build(
        stale: false, checked_at: Time.utc(2026, 1, 1), ttl_remaining_ms: 1234,
      )
      h = f.to_h_for_wire
      aggregate_failures do
        expect(h).not_to have_key("checked_at")
        expect(h).not_to have_key("ttl_remaining_ms")
      end
    end

    it "round-trips the legacy keys exactly (string keys, nil reason ok)" do
      f = described_class.build(stale: false, reason: nil, refreshing: false)
      h = f.to_h_for_wire
      aggregate_failures do
        expect(h.keys).to all(be_a(String))
        expect(h["stale"]).to be(false)
        expect(h["stale_reason"]).to be_nil
        expect(h["refreshing"]).to be(false)
      end
    end
  end

  describe "immutable update" do
    it "supports #with for non-destructive update" do
      f = described_class.build(stale: true, refreshing: false)
      f2 = f.with(refreshing: true)
      aggregate_failures do
        expect(f.refreshing).to be(false)
        expect(f2.refreshing).to be(true)
        expect(f2.stale).to be(true)
      end
    end
  end
end
