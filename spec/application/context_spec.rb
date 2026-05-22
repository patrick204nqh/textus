require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Textus::Application::Context do
  def build_store(textus_dir)
    FileUtils.mkdir_p(File.join(textus_dir, "zones", "working"))
    File.write(File.join(textus_dir, "manifest.yaml"), <<~YAML)
      version: textus/2
      zones:
        - { name: working, writable_by: [human, script] }
        - { name: canon,   writable_by: [human] }
    YAML
    Textus::Store.new(textus_dir)
  end

  it "carries store, role, correlation_id, and clock" do
    Dir.mktmpdir do |root|
      store = build_store(File.join(root, ".textus"))
      ctx = described_class.new(store: store, role: "script", correlation_id: "abc-123")
      expect(ctx.store).to equal(store)
      expect(ctx.role).to eq("script")
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
      ctx_script = described_class.new(store: store, role: "script")
      expect(ctx_human.can_write?("working")).to be(true)
      expect(ctx_script.can_write?("working")).to be(true)
      expect(ctx_human.can_write?("canon")).to be(true)
      expect(ctx_script.can_write?("canon")).to be(false)
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
end
