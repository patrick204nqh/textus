require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Textus::Write::FetchOrchestrator do
  let(:fake_events) do
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

  let(:fake_store) do
    events = fake_events
    Class.new do
      define_method(:events) { events }
    end.new
  end

  def make_orchestrator(worker, spawner: ->(**) {})
    described_class.new(
      worker: worker,
      store_root: "/tmp/fake",
      events: fake_events,
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

  describe "Action::FetchSync" do
    it "returns Outcome::Fetched when worker succeeds" do
      envelope = { "key" => "some.key", "body" => "fresh" }
      worker = fake_worker.new(envelope)
      orch = make_orchestrator(worker)

      outcome = orch.execute(Textus::Domain::Action::FetchSync.new, key: "some.key")

      expect(outcome).to be_a(Textus::Domain::Outcome::Fetched)
      expect(outcome.envelope).to eq(envelope)
    end

    it "returns Outcome::Failed when worker raises a Textus::Error" do
      worker = fake_worker.new(Textus::UsageError.new("intake blew up"))
      orch = make_orchestrator(worker)

      outcome = orch.execute(Textus::Domain::Action::FetchSync.new, key: "k")

      expect(outcome).to be_a(Textus::Domain::Outcome::Failed)
      expect(outcome.error.message).to match(/intake blew up/)
    end
  end

  describe "Action::FetchTimed" do
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
        events: fake_events,
        store_root: "/tmp/fake",
        detached_spawner: spawner,
      )

      outcome = orch.execute(
        Textus::Domain::Action::FetchTimed.new(budget_ms: 50),
        key: "slow.key",
      )

      expect(outcome).to be_a(Textus::Domain::Outcome::Detached)
      expect(spawner_calls).to include("slow.key")
      expect(fake_events.published.map(&:first)).to include(:fetch_backgrounded)
    end

    it "returns Detached without forking when the per-leaf lock is already held (Bug 1)",
       skip: ("Process.fork unavailable" unless Process.respond_to?(:fork)) do
      Dir.mktmpdir do |store_root|
        slow_worker = Class.new do
          def run(_key)
            sleep 5
            {}
          end
        end.new

        spawner_calls = []
        spawner = ->(store_root:, key:) { spawner_calls << [store_root, key] }

        # Force the single-flight probe to fail: stub Lock#try_acquire to return false.
        allow_any_instance_of(Textus::Ports::Fetch::Lock) # rubocop:disable RSpec/AnyInstance
          .to receive(:try_acquire).and_return(false)

        orch = described_class.new(
          worker: slow_worker,
          events: fake_events,
          store_root: store_root,
          detached_spawner: spawner,
        )

        outcome = orch.execute(
          Textus::Domain::Action::FetchTimed.new(budget_ms: 50),
          key: "slow.key",
        )

        expect(outcome).to be_a(Textus::Domain::Outcome::Detached)
        expect(spawner_calls).to be_empty
        expect(fake_events.published.map(&:first)).not_to include(:fetch_backgrounded)
      end
    end

    it "returns Outcome::Fetched when worker finishes within budget" do
      envelope = { "key" => "fast.key" }
      worker = fake_worker.new(envelope)
      orch = make_orchestrator(worker)

      outcome = orch.execute(
        Textus::Domain::Action::FetchTimed.new(budget_ms: 5000),
        key: "fast.key",
      )

      expect(outcome).to be_a(Textus::Domain::Outcome::Fetched)
      expect(outcome.envelope).to eq(envelope)
    end
  end
end
