require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Textus::Application::Refresh::Worker do
  # A simple test bus that records published events without going through
  # the hooks registry (avoiding the store: kwarg shape-check).
  let(:test_bus) do
    Class.new do
      attr_reader :events

      def initialize
        @events = []
      end

      def publish(event, **payload)
        @events << [event, payload]
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
        - { name: intake, write_policy: [runner] }
      entries:
        - key: intake.item
          path: intake/item.md
          zone: intake
          intake: { handler: test_intake }
    YAML

    File.write(File.join(textus, "hooks", "test_intake.rb"), intake_body)

    Textus::Store.new(textus)
  end

  it "persists the envelope and fires :refresh_started and :entry_refreshed events on success" do
    Dir.mktmpdir do |root|
      hook_body = <<~RUBY
        Textus.on(:resolve_intake, :test_intake) { |store:, config:, args:| { _meta: { "name" => "item" }, body: "hello" } }
      RUBY

      store = build_store(root, intake_body: hook_body)
      ctx = Textus::Application::Context.new(store: store, role: "runner")
      worker = described_class.new(ctx: ctx, bus: test_bus)

      envelope = worker.run("intake.item")

      expect(envelope).not_to be_nil
      expect(envelope.body).to eq("hello")

      event_names = test_bus.events.map(&:first)
      expect(event_names).to include(:refresh_started)
      expect(event_names).to include(:entry_refreshed)

      refreshed_payload = test_bus.events.find { |name, _| name == :entry_refreshed }.last
      expect(refreshed_payload[:change]).to eq(:created)
      expect(refreshed_payload[:key]).to eq("intake.item")
    end
  end

  it "fires :refresh_failed and raises UsageError when the intake handler raises StandardError" do
    Dir.mktmpdir do |root|
      hook_body = <<~RUBY
        Textus.on(:resolve_intake, :test_intake) { |store:, config:, args:| raise "something went wrong" }
      RUBY

      store = build_store(root, intake_body: hook_body)
      ctx = Textus::Application::Context.new(store: store, role: "runner")
      worker = described_class.new(ctx: ctx, bus: test_bus)

      expect do
        worker.run("intake.item")
      end.to raise_error(Textus::UsageError, /raised: RuntimeError: something went wrong/)

      failed_events = test_bus.events.filter { |ev| ev.first == :refresh_failed }
      expect(failed_events).not_to be_empty
      expect(failed_events.first.last[:key]).to eq("intake.item")
    end
  end

  def build_store_with_timeout(root, intake_body:, timeout:)
    textus = File.join(root, ".textus")
    FileUtils.mkdir_p(File.join(textus, "zones", "intake"))
    FileUtils.mkdir_p(File.join(textus, "hooks"))
    File.write(File.join(textus, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: intake, write_policy: [runner] }
      entries:
        - { key: intake.slow, path: intake/slow.md, zone: intake, intake: { handler: slow_intake } }
      rules:
        - match: intake.slow
          refresh: { ttl: 1h, on_stale: sync, fetch_timeout_seconds: #{timeout} }
    YAML
    File.write(File.join(textus, "hooks", "slow_intake.rb"), intake_body)
    Textus::Store.new(textus)
  end

  it "honors a per-rule fetch_timeout_seconds override in the timeout error message" do
    Dir.mktmpdir do |root|
      hook_body = "Textus.on(:resolve_intake, :slow_intake) { |store:, config:, args:| sleep 5 }"
      store = build_store_with_timeout(root, intake_body: hook_body, timeout: 1)
      ctx = Textus::Application::Context.new(store: store, role: "runner")
      worker = described_class.new(ctx: ctx, bus: test_bus)

      expect { worker.run("intake.slow") }
        .to raise_error(Textus::UsageError, /exceeded 1s timeout/)
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
          - { name: plain, write_policy: [human] }
        entries:
          - { key: plain.doc, path: plain/doc.md, zone: plain }
      YAML

      store = Textus::Store.new(textus)
      ctx = Textus::Application::Context.new(store: store, role: "human")
      worker = described_class.new(ctx: ctx, bus: test_bus)

      expect { worker.run("plain.doc") }
        .to raise_error(Textus::UsageError, /no intake declared/)
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
          - { name: intake, write_policy: [runner] }
        entries:
          - key: intake.vendor
            path: intake/vendor
            zone: intake
            nested: true
            intake: { handler: capturing_intake }
      YAML

      File.write(File.join(textus, "hooks", "capturing_intake.rb"), <<~RUBY)
        Textus.on(:resolve_intake, :capturing_intake) do |store:, config:, args:|
          Thread.current[:captured_args] = args
          { _meta: { "name" => "agent-eval" }, body: "x" }
        end
      RUBY

      Thread.current[:captured_args] = nil
      store = Textus::Store.new(textus)
      ctx = Textus::Application::Context.new(store: store, role: "runner")
      worker = described_class.new(ctx: ctx, bus: test_bus)

      worker.run("intake.vendor.affaan-m.agent-eval")

      expect(Thread.current[:captured_args]).to include(
        trigger_key: "intake.vendor.affaan-m.agent-eval",
        leaf_segments: %w[affaan-m agent-eval],
      )
    end
  end
end
