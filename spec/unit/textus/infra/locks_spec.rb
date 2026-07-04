require "spec_helper"
require "tmpdir"

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
