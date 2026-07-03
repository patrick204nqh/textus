require "spec_helper"
require "tmpdir"

RSpec.describe Textus::Infra::Locks::BuildLock do
  subject(:lock) { described_class.new(tmpdir) }

  let(:tmpdir) { Dir.mktmpdir }

  after { FileUtils.rm_rf(tmpdir) }

  describe "#acquire_or_raise" do
    it "acquires the lock and yields" do
      yielded = false
      lock.acquire_or_raise { yielded = true }
      expect(yielded).to be true
    end

    it "writes diagnostic content while held" do
      captured = nil
      lock.acquire_or_raise { captured = File.read(File.join(tmpdir, ".state", "ephemeral", "locks", "build.lock")) }
      expect(captured).to match(/pid=#{Process.pid}\b/)
      expect(captured).to match(/started=\d{4}-\d{2}-\d{2}T/)
      expect(captured).to match(/host=\S+/)
    end

    it "releases the lock after the block returns" do
      lock.acquire_or_raise { :noop }
      expect { described_class.new(tmpdir).acquire_or_raise { :noop } }.not_to raise_error
    end

    it "releases the lock if the block raises" do
      expect { lock.acquire_or_raise { raise "boom" } }.to raise_error("boom")
      expect { described_class.new(tmpdir).acquire_or_raise { :noop } }.not_to raise_error
    end
  end

  describe ".with" do
    it "acquires and releases" do
      yielded = false
      described_class.with(root: tmpdir) { yielded = true }
      expect(yielded).to be true
    end
  end
end

RSpec.describe Textus::Infra::Locks::WatcherLock do
  subject(:lock) { described_class.new(tmpdir) }

  let(:tmpdir) { Dir.mktmpdir }

  after do
    begin
      lock.release
    rescue StandardError
      nil
    end
    FileUtils.rm_rf(tmpdir)
  end

  describe "#acquire" do
    it "acquires the lock" do
      lock.acquire
      expect(described_class.running?(tmpdir)).to be true
    end
  end

  describe "#release" do
    it "releases the lock" do
      lock.acquire
      lock.release
      expect(described_class.running?(tmpdir)).to be false
    end
  end

  describe ".running?" do
    it "returns false when no lock is held" do
      expect(described_class.running?(tmpdir)).to be false
    end

    it "returns true when lock is held" do
      lock.acquire
      expect(described_class.running?(tmpdir)).to be true
    end
  end
end
