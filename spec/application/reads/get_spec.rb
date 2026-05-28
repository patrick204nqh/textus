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
        - { key: working.doc, path: working/doc.md, zone: working, kind: leaf}

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
          kind: intake
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
      Textus.hook do |reg|
        reg.on(:resolve_intake, :test_intake) { |store:, config:, args:| { _meta: { "name" => "doc" }, body: "fresh" } }
      end
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

  it "returns nil when the file does not exist on disk" do
    Dir.mktmpdir do |root|
      store = build_store_no_intake(root)
      ctx = Textus::Application::Context.build(role: "runner")
      use_case = described_class.new(ctx: ctx, ports: Textus::Application::Ports.from_store(store))
      expect(use_case.call("working.doc")).to be_nil
    end
  end

  it "annotates as fresh when no refresh policy applies" do
    Dir.mktmpdir do |root|
      store = build_store_no_intake(root)
      write_doc(root)
      ctx = Textus::Application::Context.build(role: "runner")
      env = described_class.new(ctx: ctx, ports: Textus::Application::Ports.from_store(store)).call("working.doc")
      expect(env.freshness.stale).to be(false)
      expect(env.freshness.refreshing).to be(false)
    end
  end

  it "annotates as fresh when the envelope is within TTL" do
    Dir.mktmpdir do |root|
      store = build_store_with_intake(root, ttl: "1h", on_stale: "warn")
      write_doc(root, last_refreshed_at: Time.now.utc.iso8601)
      ctx = Textus::Application::Context.build(role: "runner")
      env = described_class.new(ctx: ctx, ports: Textus::Application::Ports.from_store(store)).call("working.doc")
      expect(env.freshness.stale).to be(false)
    end
  end

  it "annotates as stale when the envelope is past TTL — but does NOT refresh" do
    Dir.mktmpdir do |root|
      store = build_store_with_intake(root, ttl: "1s", on_stale: "timed_sync")
      write_doc(root, last_refreshed_at: "2020-01-01T00:00:00Z")
      ctx = Textus::Application::Context.build(role: "runner")
      env = described_class.new(ctx: ctx, ports: Textus::Application::Ports.from_store(store)).call("working.doc")
      expect(env.freshness.stale).to be(true)
      expect(env.freshness.refreshing).to be(false)
    end
  end

  it "does not accept an orchestrator: kwarg (signal of the contract)" do
    Dir.mktmpdir do |root|
      store = build_store_no_intake(root)
      ctx = Textus::Application::Context.build(role: "runner")
      expect do
        described_class.new(ctx: ctx, ports: Textus::Application::Ports.from_store(store), orchestrator: Object.new)
      end.to raise_error(ArgumentError, /unknown keyword: :orchestrator/)
    end
  end
end
