require "spec_helper"

RSpec.describe Textus::Domain::Freshness::Policy do
  describe "#decide" do
    let(:fresh_verdict) { Textus::Domain::Freshness::Verdict.fresh }
    let(:stale_verdict) { Textus::Domain::Freshness::Verdict.stale("ttl exceeded") }

    it "returns Action::Return when verdict is fresh, regardless of on_stale" do
      policy = described_class.new(ttl_seconds: 600, on_stale: :timed_sync, sync_budget_ms: 500)
      expect(policy.decide(fresh_verdict)).to be_a(Textus::Domain::Action::Return)
    end

    it "returns Action::Return when on_stale is :warn" do
      policy = described_class.new(ttl_seconds: 600, on_stale: :warn, sync_budget_ms: 500)
      expect(policy.decide(stale_verdict)).to be_a(Textus::Domain::Action::Return)
    end

    it "returns Action::FetchSync when on_stale is :sync" do
      policy = described_class.new(ttl_seconds: 600, on_stale: :sync, sync_budget_ms: 500)
      expect(policy.decide(stale_verdict)).to be_a(Textus::Domain::Action::FetchSync)
    end

    it "returns Action::FetchTimed with budget_ms when on_stale is :timed_sync" do
      policy = described_class.new(ttl_seconds: 600, on_stale: :timed_sync, sync_budget_ms: 500)
      action = policy.decide(stale_verdict)
      expect(action).to be_a(Textus::Domain::Action::FetchTimed)
      expect(action.budget_ms).to eq(500)
    end
  end
end
