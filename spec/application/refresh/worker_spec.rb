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
    FileUtils.mkdir_p(File.join(textus, "zones", "inbox"))
    FileUtils.mkdir_p(File.join(textus, "hooks"))

    File.write(File.join(textus, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: inbox, writable_by: [script] }
      entries:
        - key: inbox.item
          path: inbox/item.md
          zone: inbox
          intake: { handler: test_intake }
    YAML

    File.write(File.join(textus, "hooks", "test_intake.rb"), intake_body)

    Textus::Store.new(textus)
  end

  it "persists the envelope and fires :refresh_began and :refreshed events on success" do
    Dir.mktmpdir do |root|
      hook_body = <<~RUBY
        Textus.intake(:test_intake) { |store:, config:, args:| { _meta: { "name" => "item" }, body: "hello" } }
      RUBY

      store = build_store(root, intake_body: hook_body)
      ctx = Textus::Application::Context.new(store: store, role: "script")
      worker = described_class.new(ctx: ctx, bus: test_bus)

      envelope = worker.run("inbox.item")

      expect(envelope).not_to be_nil
      expect(envelope["body"]).to eq("hello")

      event_names = test_bus.events.map(&:first)
      expect(event_names).to include(:refresh_began)
      expect(event_names).to include(:refreshed)

      refreshed_payload = test_bus.events.find { |name, _| name == :refreshed }.last
      expect(refreshed_payload[:change]).to eq(:created)
      expect(refreshed_payload[:key]).to eq("inbox.item")
    end
  end

  it "fires :refresh_failed and raises UsageError when the intake handler raises StandardError" do
    Dir.mktmpdir do |root|
      hook_body = <<~RUBY
        Textus.intake(:test_intake) { |store:, config:, args:| raise "something went wrong" }
      RUBY

      store = build_store(root, intake_body: hook_body)
      ctx = Textus::Application::Context.new(store: store, role: "script")
      worker = described_class.new(ctx: ctx, bus: test_bus)

      expect do
        worker.run("inbox.item")
      end.to raise_error(Textus::UsageError, /raised: RuntimeError: something went wrong/)

      failed_events = test_bus.events.filter { |ev| ev.first == :refresh_failed }
      expect(failed_events).not_to be_empty
      expect(failed_events.first.last[:key]).to eq("inbox.item")
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
          - { name: plain, writable_by: [human] }
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
end
