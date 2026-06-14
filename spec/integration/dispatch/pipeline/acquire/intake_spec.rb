require "spec_helper"

RSpec.describe Textus::Dispatch::Pipeline::Acquire::Intake do
  # A simple test events object that records published events, delegating nothing.
  def make_test_events(registry)
    events = []
    allow(registry).to receive(:publish) do |event, **payload|
      events << [event, payload]
      Textus::Step::FireReport.new(fired: [], errored: [], timed_out: [])
    end
    Struct.new(:events).new(events)
  end

  def build_store(root, intake_body:)
    textus = File.join(root, ".textus")
    FileUtils.mkdir_p(File.join(textus, "data", "intake"))
    FileUtils.mkdir_p(File.join(textus, "steps", "fetch"))

    File.write(File.join(textus, "manifest.yaml"), <<~YAML)
      version: textus/3
      lanes:
        - { name: intake, kind: machine }
      entries:
        - key: intake.item
          kind: produced
          path: intake/item.md
          lane: intake
          source: { from: fetch, handler: test_intake }
    YAML

    # Use a unique class name for each store to avoid collisions across tests
    unique_id = SecureRandom.hex(4)
    # But wait, the handler name in manifest is 'test_intake'.
    # The loader derives the name from the filename, not the class name.
    # So the class name doesn't matter as long as it's a Step::Base subclass.

    # Let's just wrap the provided body in a uniquely named class.
    # We need to make sure the body doesn't already contain 'class ...'

    # Actually, the simplest way is to just write the body as provided,
    # but ensure it's a unique class.

    # Let's modify the tests to provide only the method definitions.
    File.write(File.join(textus, "steps", "fetch", "test_intake.rb"),
               "class TestIntakeFetch#{unique_id} < Textus::Step::Fetch\n#{intake_body}\nend")

    Textus::Store.new(textus)
  end

  it "persists the envelope and fires :entry_fetch_started and :entry_fetched events on success" do
    Dir.mktmpdir do |root|
      hook_body = <<~RUBY
        def call(config:, args:, **)
          { _meta: { "name" => "item" }, body: "hello" }
        end
      RUBY

      store = build_store(root, intake_body: hook_body)
      test_events = make_test_events(store.container.steps)
      ctx = test_ctx(role: "automation")
      worker = build_worker(store, ctx)

      envelope = worker.run("intake.item")

      expect(envelope).not_to be_nil
      expect(envelope.body).to eq("hello")

      event_names = test_events.events.map(&:first)
      expect(event_names).to include(:entry_fetch_started)
      expect(event_names).to include(:entry_fetched)

      fetched_payload = test_events.events.find { |name, _| name == :entry_fetched }.last
      expect(fetched_payload[:change]).to eq(:created)
      expect(fetched_payload[:key]).to eq("intake.item")
    end
  end

  it "fires :entry_fetch_failed and raises UsageError when the intake handler raises StandardError" do
    Dir.mktmpdir do |root|
      hook_body = <<~RUBY
        def call(config:, args:, **)
          raise "something went wrong"
        end
      RUBY

      store = build_store(root, intake_body: hook_body)
      test_events = make_test_events(store.container.steps)
      ctx = test_ctx(role: "automation")
      worker = build_worker(store, ctx)

      expect do
        worker.run("intake.item")
      end.to raise_error(Textus::UsageError, /raised: RuntimeError: something went wrong/)

      failed_events = test_events.events.filter { |ev| ev.first == :entry_fetch_failed }
      expect(failed_events).not_to be_empty
      expect(failed_events.first.last[:key]).to eq("intake.item")
    end
  end

  it "raises UsageError immediately when the key has no intake handler" do
    Dir.mktmpdir do |root|
      textus = File.join(root, ".textus")
      FileUtils.mkdir_p(File.join(textus, "data", "plain"))
      FileUtils.mkdir_p(File.join(textus, "hooks"))

      File.write(File.join(textus, "manifest.yaml"), <<~YAML)
        version: textus/3
        lanes:
          - { name: plain, kind: canon }
        entries:
          - { key: plain.doc, path: plain/doc.md, lane: plain, kind: leaf}

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
      FileUtils.mkdir_p(File.join(textus, "data", "intake", "vendor"))
      FileUtils.mkdir_p(File.join(textus, "hooks"))

      File.write(File.join(textus, "manifest.yaml"), <<~YAML)
        version: textus/3
        lanes:
          - { name: intake, kind: machine }
        entries:
          - key: intake.vendor
            kind: produced
            path: intake/vendor
            lane: intake
            nested: true
            source: { from: fetch, handler: capturing_intake }
      YAML

      unique_id = SecureRandom.hex(4)
      FileUtils.mkdir_p(File.join(textus, "steps", "fetch"))
      File.write(File.join(textus, "steps", "fetch", "capturing_intake.rb"), <<~RUBY)
        class CapturingIntakeFetch#{unique_id} < Textus::Step::Fetch
          def call(config:, args:, **)
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
