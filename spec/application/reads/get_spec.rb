require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Textus::Application::Reads::Get do
  def build_store_no_intake(root)
    textus = File.join(root, ".textus")
    FileUtils.mkdir_p(File.join(textus, "zones", "working"))
    FileUtils.mkdir_p(File.join(textus, "hooks"))

    File.write(File.join(textus, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: working, write_policy: [human, runner] }
      entries:
        - { key: working.doc, path: working/doc.md, zone: working }
    YAML

    Textus::Store.new(textus)
  end

  def build_store_with_intake(root, ttl:, on_stale: "warn")
    textus = File.join(root, ".textus")
    FileUtils.mkdir_p(File.join(textus, "zones", "working"))
    FileUtils.mkdir_p(File.join(textus, "hooks"))

    File.write(File.join(textus, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: working, write_policy: [human, runner] }
      entries:
        - key: working.doc
          path: working/doc.md
          zone: working
          intake:
            handler: test_intake
      rules:
        - match: working.doc
          refresh:
            ttl: "#{ttl}"
            on_stale: #{on_stale}
    YAML

    File.write(File.join(textus, "hooks", "test_intake.rb"), <<~RUBY)
      Textus.on(:intake, :test_intake) { |store:, config:, args:| { _meta: { "name" => "doc" }, body: "fresh" } }
    RUBY

    Textus::Store.new(textus)
  end

  def write_doc(root, last_refreshed_at: Time.now.utc.iso8601)
    textus = File.join(root, ".textus")
    File.write(File.join(textus, "zones", "working", "doc.md"), <<~MD)
      ---
      name: doc
      last_refreshed_at: "#{last_refreshed_at}"
      ---
      stored body
    MD
  end

  let(:fake_orchestrator) do
    Class.new do
      def execute(_action, key: nil, as: nil) # rubocop:disable Lint/UnusedMethodArgument
        Textus::Domain::Outcome::Skipped.new
      end
    end.new
  end

  it "returns annotated envelope with stale=false and refreshing=false when entry is fresh" do
    Dir.mktmpdir do |root|
      store = build_store_with_intake(root, ttl: "1h", on_stale: "warn")
      write_doc(root, last_refreshed_at: Time.now.utc.iso8601)

      ctx = Textus::Application::Context.new(store: store, role: "runner")
      use_case = described_class.new(ctx: ctx, orchestrator: fake_orchestrator)
      envelope = use_case.call("working.doc")

      expect(envelope).not_to be_nil
      expect(envelope["stale"]).to be(false)
      expect(envelope["refreshing"]).to be(false)
    end
  end

  it "returns nil when the file does not exist on disk" do
    Dir.mktmpdir do |root|
      store = build_store_no_intake(root)
      # Do NOT write the file — leave the zone dir empty.

      ctx = Textus::Application::Context.new(store: store, role: "runner")
      use_case = described_class.new(ctx: ctx, orchestrator: fake_orchestrator)
      result = use_case.call("working.doc")

      expect(result).to be_nil
    end
  end

  it "annotates as stale when verdict is stale and orchestrator returns Skipped" do
    Dir.mktmpdir do |root|
      store = build_store_with_intake(root, ttl: "1s", on_stale: "warn")
      write_doc(root, last_refreshed_at: "2020-01-01T00:00:00Z")

      ctx = Textus::Application::Context.new(store: store, role: "runner")
      use_case = described_class.new(ctx: ctx, orchestrator: fake_orchestrator)
      envelope = use_case.call("working.doc")

      expect(envelope["stale"]).to be(true)
      expect(envelope["refreshing"]).to be(false)
    end
  end
end
