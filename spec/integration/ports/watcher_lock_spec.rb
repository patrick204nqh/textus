require "spec_helper"

RSpec.describe Textus::Port::WatcherLock do
  include_context "textus_store_fixture"

  it "reports not running when lock file does not exist" do
    expect(described_class.running?(root)).to be(false)
  end

  it "reports running while lock is held" do
    lock = described_class.new(root)
    lock.acquire
    expect(described_class.running?(root)).to be(true)
    lock.release
    expect(described_class.running?(root)).to be(false)
  end

  it "lock path is under .state/" do
    expect(Textus::StoreGeometry.new(root).lock_path("watcher")).to include(".state")
    expect(Textus::StoreGeometry.new(root).lock_path("watcher")).to end_with("watcher.lock")
  end
end
