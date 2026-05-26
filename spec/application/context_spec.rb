require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Textus::Application::Context do
  def build_store(textus_dir)
    FileUtils.mkdir_p(File.join(textus_dir, "zones", "working"))
    File.write(File.join(textus_dir, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: working, write_policy: [human, runner] }
        - { name: identity,   write_policy: [human] }
    YAML
    Textus::Store.new(textus_dir)
  end

  it "carries store, role, correlation_id, and clock" do
    Dir.mktmpdir do |root|
      store = build_store(File.join(root, ".textus"))
      ctx = described_class.new(store: store, role: "runner", correlation_id: "abc-123")
      expect(ctx.store).to equal(store)
      expect(ctx.role).to eq("runner")
      expect(ctx.correlation_id).to eq("abc-123")
    end
  end

  it "generates a correlation_id if omitted" do
    Dir.mktmpdir do |root|
      store = build_store(File.join(root, ".textus"))
      ctx = described_class.new(store: store, role: "human")
      expect(ctx.correlation_id).to match(/\A[0-9a-f-]{36}\z/)
    end
  end

  it "answers can_write?(zone) by consulting Domain::Permission" do
    Dir.mktmpdir do |root|
      store = build_store(File.join(root, ".textus"))
      ctx_human  = described_class.new(store: store, role: "human")
      ctx_script = described_class.new(store: store, role: "runner")
      expect(ctx_human.can_write?("working")).to be(true)
      expect(ctx_script.can_write?("working")).to be(true)
      expect(ctx_human.can_write?("identity")).to be(true)
      expect(ctx_script.can_write?("identity")).to be(false)
    end
  end

  it "returns frozen ctx.now within a single request lifetime" do
    Dir.mktmpdir do |root|
      store = build_store(File.join(root, ".textus"))
      fake_clock = Class.new do
        def self.now
          Time.utc(2026, 5, 22, 12, 0, 0)
        end
      end
      ctx = described_class.new(store: store, role: "human", clock: fake_clock)
      first = ctx.now
      sleep 0.01
      second = ctx.now
      expect(first).to eq(second)
    end
  end

  describe "#bus" do
    it "returns the store's bus" do
      Dir.mktmpdir do |root|
        store = build_store(File.join(root, ".textus"))
        ctx = described_class.new(store: store, role: "human")
        expect(ctx.bus).to equal(store.bus)
      end
    end
  end

  describe "#authorize_write!" do
    it "returns nil when the role can write to the mentry's zone" do
      Dir.mktmpdir do |root|
        store = build_store(File.join(root, ".textus"))
        ctx = described_class.new(store: store, role: "runner")
        mentry = Struct.new(:key, :zone).new("working.foo", "working")
        expect(ctx.authorize_write!(mentry)).to be_nil
      end
    end

    it "raises WriteForbidden with writers/zone/key details when the role lacks write" do
      Dir.mktmpdir do |root|
        store = build_store(File.join(root, ".textus"))
        ctx = described_class.new(store: store, role: "runner")
        mentry = Struct.new(:key, :zone).new("identity.self", "identity")
        expect { ctx.authorize_write!(mentry) }.to raise_error(Textus::WriteForbidden) do |err|
          expect(err.details["key"]).to eq("identity.self")
          expect(err.details["zone"]).to eq("identity")
          expect(err.details["writers"]).to eq(["human"])
        end
      end
    end
  end

  describe "#authorize_read!" do
    it "returns nil when the role can read the mentry's zone" do
      Dir.mktmpdir do |root|
        store = build_store(File.join(root, ".textus"))
        ctx = described_class.new(store: store, role: "runner")
        mentry = Struct.new(:key, :zone).new("working.foo", "working")
        expect(ctx.authorize_read!(mentry)).to be_nil
      end
    end
  end

  describe ".system" do
    it "returns a human-role context bound to the store" do
      Dir.mktmpdir do |root|
        store = build_store(File.join(root, ".textus"))
        ctx = described_class.system(store)
        expect(ctx).to be_a(described_class)
        expect(ctx.role).to eq("human")
        expect(ctx.store).to equal(store)
        expect(ctx.correlation_id).to be_a(String)
      end
    end
  end
end
