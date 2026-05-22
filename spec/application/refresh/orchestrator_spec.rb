require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Textus::Application::Refresh::Orchestrator do
  let(:fake_bus) do
    Class.new do
      attr_reader :published

      def initialize
        @published = []
      end

      def publish(event, **payload)
        @published << [event, payload]
      end
    end.new
  end

  let(:fake_worker) do
    Class.new do
      attr_accessor :result

      def initialize(result)
        @result = result
      end

      def run(_key)
        raise @result if @result.is_a?(Exception)

        @result
      end
    end
  end

  def make_orchestrator(worker, spawner: ->(**) {})
    described_class.new(
      worker: worker,
      bus: fake_bus,
      store_root: "/tmp/fake",
      detached_spawner: spawner,
    )
  end

  describe "Action::Return" do
    it "returns Outcome::Skipped without calling the worker" do
      worker = fake_worker.new({ "key" => "k" })
      orch = make_orchestrator(worker)

      outcome = orch.execute(Textus::Domain::Action::Return.new, key: "k")

      expect(outcome).to be_a(Textus::Domain::Outcome::Skipped)
    end
  end

  describe "Action::RefreshSync" do
    it "returns Outcome::Refreshed when worker succeeds" do
      envelope = { "key" => "some.key", "body" => "fresh" }
      worker = fake_worker.new(envelope)
      orch = make_orchestrator(worker)

      outcome = orch.execute(Textus::Domain::Action::RefreshSync.new, key: "some.key")

      expect(outcome).to be_a(Textus::Domain::Outcome::Refreshed)
      expect(outcome.envelope).to eq(envelope)
    end

    it "returns Outcome::Failed when worker raises a Textus::Error" do
      worker = fake_worker.new(Textus::UsageError.new("intake blew up"))
      orch = make_orchestrator(worker)

      outcome = orch.execute(Textus::Domain::Action::RefreshSync.new, key: "k")

      expect(outcome).to be_a(Textus::Domain::Outcome::Failed)
      expect(outcome.error.message).to match(/intake blew up/)
    end
  end

  describe "Action::RefreshTimed" do
    it "returns Outcome::Detached and calls spawner when worker exceeds budget",
       skip: ("Process.fork unavailable" unless Process.respond_to?(:fork)) do
      slow_worker = Class.new do
        def run(_key)
          sleep 5
          {}
        end
      end.new

      spawner_calls = []
      spawner = ->(store_root:, key:) { spawner_calls << key } # rubocop:disable Lint/UnusedBlockArgument

      orch = described_class.new(
        worker: slow_worker,
        bus: fake_bus,
        store_root: "/tmp/fake",
        detached_spawner: spawner,
      )

      outcome = orch.execute(
        Textus::Domain::Action::RefreshTimed.new(budget_ms: 50),
        key: "slow.key",
      )

      expect(outcome).to be_a(Textus::Domain::Outcome::Detached)
      expect(spawner_calls).to include("slow.key")
      expect(fake_bus.published.map(&:first)).to include(:refresh_detached)
    end

    it "returns Outcome::Refreshed when worker finishes within budget" do
      envelope = { "key" => "fast.key" }
      worker = fake_worker.new(envelope)
      orch = make_orchestrator(worker)

      outcome = orch.execute(
        Textus::Domain::Action::RefreshTimed.new(budget_ms: 5000),
        key: "fast.key",
      )

      expect(outcome).to be_a(Textus::Domain::Outcome::Refreshed)
      expect(outcome.envelope).to eq(envelope)
    end
  end
end
