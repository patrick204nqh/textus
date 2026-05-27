require "spec_helper"

RSpec.describe Textus::Domain::Freshness::Evaluator do
  let(:now) { Time.parse("2026-05-22T12:00:00Z") }
  let(:mentry) do
    instance_double(
      Textus::Manifest::Entry::Base,
      zone: "working", owner: "human", format: "markdown", schema: nil,
    )
  end

  def policy(ttl: 600)
    Textus::Domain::Freshness::Policy.new(ttl_seconds: ttl, on_stale: :warn, sync_budget_ms: 500)
  end

  def env_with(meta)
    Textus::Envelope.build(key: "k", mentry: mentry, path: "/x", meta: meta, body: "", etag: "e")
  end

  it "returns fresh verdict when ttl_seconds is nil" do
    verdict = described_class.call(policy(ttl: nil), env_with({}), now: now)
    expect(verdict.fresh?).to be(true)
  end

  it "returns fresh when last_refreshed_at + ttl > now" do
    last = (now - 60).utc.iso8601
    expect(described_class.call(policy, env_with({ "last_refreshed_at" => last }), now: now).fresh?).to be(true)
  end

  it "returns stale when last_refreshed_at + ttl < now" do
    last = (now - 1200).utc.iso8601
    verdict = described_class.call(policy, env_with({ "last_refreshed_at" => last }), now: now)
    aggregate_failures do
      expect(verdict.stale?).to be(true)
      expect(verdict.reason).to match(/ttl exceeded/)
    end
  end

  it "returns stale when last_refreshed_at missing" do
    verdict = described_class.call(policy, env_with({}), now: now)
    aggregate_failures do
      expect(verdict.stale?).to be(true)
      expect(verdict.reason).to eq("never refreshed")
    end
  end

  it "returns stale when last_refreshed_at unparseable" do
    verdict = described_class.call(policy, env_with({ "last_refreshed_at" => "garbage" }), now: now)
    aggregate_failures do
      expect(verdict.stale?).to be(true)
      expect(verdict.reason).to match(/unparseable/)
    end
  end
end
