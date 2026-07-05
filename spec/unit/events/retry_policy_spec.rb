require "spec_helper"

RSpec.describe Textus::Workflow::RetryPolicy do
  subject(:policy) { described_class.new }

  describe "#decide" do
    it "is terminal when retry_count has reached max_attempts" do
      decision = policy.decide(retry_count: 3, max_attempts: 3)
      expect(decision).to be_terminal
    end

    it "is terminal when retry_count exceeds max_attempts" do
      decision = policy.decide(retry_count: 5, max_attempts: 3)
      expect(decision).to be_terminal
    end

    it "is not terminal and returns the first backoff delay on the first retry" do
      decision = policy.decide(retry_count: 1, max_attempts: 3)
      expect(decision).not_to be_terminal
      expect(decision.delay).to eq(10)
    end

    it "returns increasing delays for later retries" do
      expect(policy.decide(retry_count: 2, max_attempts: 5).delay).to eq(30)
      expect(policy.decide(retry_count: 3, max_attempts: 5).delay).to eq(60)
    end

    it "clamps delay to the longest configured backoff for retries beyond the curve" do
      decision = policy.decide(retry_count: 10, max_attempts: 20)
      expect(decision.delay).to eq(60)
    end

    it "accepts a custom backoff curve" do
      custom = described_class.new(backoff_delays: [5, 15])
      expect(custom.decide(retry_count: 1, max_attempts: 3).delay).to eq(5)
      expect(custom.decide(retry_count: 2, max_attempts: 3).delay).to eq(15)
      expect(custom.decide(retry_count: 3, max_attempts: 4).delay).to eq(15)
    end
  end
end
