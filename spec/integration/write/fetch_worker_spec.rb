require "spec_helper"

RSpec.describe Textus::Write::FetchWorker do
  # A simple test events object that records published events, delegating nothing.
  def make_test_events
    Class.new do
      attr_reader :events

      def initialize
        @events = []
      end

      def publish(event, **payload)
        @events << [event, payload]
        Textus::Hooks::FireReport.new(fired: [], errored: [], timed_out: [])
      end

      def error_log
        Textus::Hooks::ErrorLog.new
      end
    end.new
  end

  def build_store(root, intake_body:)
    textus = File.join(root, ".textus")
    FileUtils.mkdir_p(File.join(textus, "zones", "intake"))
    FileUtils.mkdir_p(File.join(textus, "hooks"))

    File.write(File.join(textus, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: intake, kind: machine }
      entries:
        - key: intake.item
          kind: intake
          path: intake/item.md
          zone: intake
          intake: { handler: test_intake }
    YAML

    File.write(File.join(textus, "hooks", "test_intake.rb"), intake_body)

    Textus::Store.new(textus)
  end

  it "persists the envelope and fires :fetch_started and :entry_fetched events on success" do
    Dir.mktmpdir do |root|
      hook_body = <<~RUBY
        Textus.hook do |reg|
          reg.on(:resolve_intake, :test_intake) { |caps:, config:, args:| { _meta: { "name" => "item" }, body: "hello" } }
        end
      RUBY

      store = build_store(root, intake_body: hook_body)
      test_events = make_test_events
      ctx = test_ctx(role: "automation")
      worker = build_worker(store, ctx, events: test_events)

      envelope = worker.run("intake.item")

      expect(envelope).not_to be_nil
      expect(envelope.body).to eq("hello")

      event_names = test_events.events.map(&:first)
      expect(event_names).to include(:fetch_started)
      expect(event_names).to include(:entry_fetched)

      fetched_payload = test_events.events.find { |name, _| name == :entry_fetched }.last
      expect(fetched_payload[:change]).to eq(:created)
      expect(fetched_payload[:key]).to eq("intake.item")
    end
  end

  it "fires :fetch_failed and raises UsageError when the intake handler raises StandardError" do
    Dir.mktmpdir do |root|
      hook_body = <<~RUBY
        Textus.hook do |reg|
          reg.on(:resolve_intake, :test_intake) { |caps:, config:, args:| raise "something went wrong" }
        end
      RUBY

      store = build_store(root, intake_body: hook_body)
      test_events = make_test_events
      ctx = test_ctx(role: "automation")
      worker = build_worker(store, ctx, events: test_events)

      expect do
        worker.run("intake.item")
      end.to raise_error(Textus::UsageError, /raised: RuntimeError: something went wrong/)

      failed_events = test_events.events.filter { |ev| ev.first == :fetch_failed }
      expect(failed_events).not_to be_empty
      expect(failed_events.first.last[:key]).to eq("intake.item")
    end
  end

  it "raises UsageError immediately when the key has no intake handler" do
    Dir.mktmpdir do |root|
      textus = File.join(root, ".textus")
      FileUtils.mkdir_p(File.join(textus, "zones", "plain"))
      FileUtils.mkdir_p(File.join(textus, "hooks"))

      File.write(File.join(textus, "manifest.yaml"), <<~YAML)
        version: textus/3
        zones:
          - { name: plain, kind: canon }
        entries:
          - { key: plain.doc, path: plain/doc.md, zone: plain, kind: leaf}

      YAML

      store = Textus::Store.new(textus)
      ctx = test_ctx(role: "human")
      worker = build_worker(store, ctx)

      expect { worker.run("plain.doc") }
        .to raise_error(Textus::UsageError, /no intake declared/)
    end
  end

  describe "#normalize_action_result" do
    it "wraps body strings for markdown" do
      out = described_class.normalize_action_result({ "body" => "hi" }, format: "markdown")
      expect(out).to eq(meta: {}, body: "hi", content: nil)
    end

    it "raises for json with neither body nor content" do
      expect do
        described_class.normalize_action_result({}, format: "json")
      end.to raise_error(Textus::UsageError, /neither content nor body/)
    end
  end

  it "passes trigger_key and leaf_segments in args (issue #59 follow-up: Bug 2)" do # rubocop:disable RSpec/ExampleLength
    Dir.mktmpdir do |root|
      textus = File.join(root, ".textus")
      FileUtils.mkdir_p(File.join(textus, "zones", "intake", "vendor"))
      FileUtils.mkdir_p(File.join(textus, "hooks"))

      File.write(File.join(textus, "manifest.yaml"), <<~YAML)
        version: textus/3
        zones:
          - { name: intake, kind: machine }
        entries:
          - key: intake.vendor
            kind: intake
            path: intake/vendor
            zone: intake
            nested: true
            intake: { handler: capturing_intake }
      YAML

      File.write(File.join(textus, "hooks", "capturing_intake.rb"), <<~RUBY)
        Textus.hook do |reg|
          reg.on(:resolve_intake, :capturing_intake) do |caps:, config:, args:|
            Thread.current[:captured_args] = args
            { _meta: { "name" => "agent-eval" }, body: "x" }
          end
        end
      RUBY

      Thread.current[:captured_args] = nil
      store = Textus::Store.new(textus)
      ctx = test_ctx(role: "automation")
      worker = build_worker(store, ctx)

      worker.run("intake.vendor.affaan-m.agent-eval")

      expect(Thread.current[:captured_args]).to include(
        trigger_key: "intake.vendor.affaan-m.agent-eval",
        leaf_segments: %w[affaan-m agent-eval],
      )
    end
  end
end
