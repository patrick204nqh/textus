require "spec_helper"

RSpec.describe Textus::Write::RefreshOrchestrator, "cooperative fallback" do # rubocop:disable RSpec/DescribeMethod
  let(:fake_worker) do
    Class.new do
      attr_reader :calls

      def initialize
        @calls = 0
      end

      def run(_key)
        @calls += 1
        OpenStruct.new(uid: "u", etag: "e") # rubocop:disable Style/OpenStructUse
      end
    end.new
  end

  before do
    require "ostruct"
    allow(Textus::Infra::Refresh::Detached).to receive(:supported?).and_return(false)
  end

  it "uses cooperative-cancel fallback when fork is unavailable and budget is met" do
    orch = described_class.new(worker: fake_worker, store_root: "/tmp/fake-store",
                               events: instance_double(Textus::Hooks::EventBus, publish: nil))
    outcome = orch.execute(Textus::Domain::Action::RefreshTimed.new(budget_ms: 1000), key: "k")
    expect(outcome).to be_a(Textus::Domain::Outcome::Refreshed)
  end

  it "returns Failed (timeout) when fork is unavailable and budget is exceeded" do
    slow_worker = Class.new do
      def run(_key)
        sleep 0.5
        raise "should not reach"
      end
    end.new
    orch = described_class.new(worker: slow_worker, store_root: "/tmp/fake-store",
                               events: instance_double(Textus::Hooks::EventBus, publish: nil))
    outcome = orch.execute(Textus::Domain::Action::RefreshTimed.new(budget_ms: 50), key: "k")
    expect(outcome).to be_a(Textus::Domain::Outcome::Failed)
    expect(outcome.error.message).to match(/timed.out|exceeded budget/i)
  end
end
