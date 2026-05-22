require "spec_helper"

RSpec.describe Textus::Domain::Freshness::Evaluator do
  let(:now) { Time.parse("2026-05-22T12:00:00Z") }

  def policy(ttl: 600)
    Textus::Domain::Freshness::Policy.new(ttl_seconds: ttl, on_stale: :warn, sync_budget_ms: 500)
  end

  it "returns fresh verdict when ttl_seconds is nil" do
    verdict = described_class.call(policy(ttl: nil), { "_meta" => {} }, now: now)
    expect(verdict.fresh?).to be(true)
  end

  it "returns fresh when last_refreshed_at + ttl > now" do
    last = (now - 60).utc.iso8601
    envelope = { "_meta" => { "last_refreshed_at" => last } }
    expect(described_class.call(policy, envelope, now: now).fresh?).to be(true)
  end

  it "returns stale when last_refreshed_at + ttl < now" do
    last = (now - 1200).utc.iso8601
    envelope = { "_meta" => { "last_refreshed_at" => last } }
    verdict = described_class.call(policy, envelope, now: now)
    expect(verdict.stale?).to be(true)
    expect(verdict.reason).to match(/ttl exceeded/)
  end

  it "returns stale when last_refreshed_at missing" do
    verdict = described_class.call(policy, { "_meta" => {} }, now: now)
    expect(verdict.stale?).to be(true)
    expect(verdict.reason).to eq("never refreshed")
  end

  it "returns stale when last_refreshed_at unparseable" do
    envelope = { "_meta" => { "last_refreshed_at" => "garbage" } }
    verdict = described_class.call(policy, envelope, now: now)
    expect(verdict.stale?).to be(true)
    expect(verdict.reason).to match(/unparseable/)
  end
end
