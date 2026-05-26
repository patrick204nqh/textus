require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe Textus::Infra::BuildLock do
  include_context "textus_store_fixture"

  before { FileUtils.mkdir_p(root) }

  it "yields the block when no other holder exists" do
    yielded = false
    described_class.with(root: root) { yielded = true }
    expect(yielded).to be true
  end

  it "writes pid/start/host diagnostic content while held" do
    captured = nil
    described_class.with(root: root) do
      captured = File.read(File.join(root, ".build.lock"))
    end
    expect(captured).to match(/pid=#{Process.pid}\b/)
    expect(captured).to match(/started=\d{4}-\d{2}-\d{2}T/)
    expect(captured).to match(/host=\S+/)
  end

  it "releases the lock after the block returns" do
    described_class.with(root: root) { :noop }
    expect { described_class.with(root: root) { :noop } }.not_to raise_error
  end

  it "releases the lock if the block raises" do
    expect do
      described_class.with(root: root) { raise "boom" }
    end.to raise_error("boom")
    expect { described_class.with(root: root) { :noop } }.not_to raise_error
  end
end
