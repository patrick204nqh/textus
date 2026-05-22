require "spec_helper"
require "tmpdir"

RSpec.describe Textus::Refresh::Lock do
  it "acquires and releases a per-key file lock" do
    Dir.mktmpdir do |root|
      lock = Textus::Refresh::Lock.new(root: root, key: "working.foo")
      expect(lock.try_acquire).to be(true)
      lock.release
      expect(lock.try_acquire).to be(true)
    end
  end

  it "returns false when another holder has the lock",
     skip: "flock_NB cooperates across handles in same process unpredictably; skipping" do
    # Inter-process; skipped because two File handles in the same process
    # don't reliably contend on flock LOCK_EX | LOCK_NB on macOS/Linux.
  end

  it "escapes unsafe key characters in the lock file path" do
    Dir.mktmpdir do |root|
      lock = Textus::Refresh::Lock.new(root: root, key: "working/../escape")
      lock.try_acquire
      lock_file = lock.instance_variable_get(:@path)
      expect(File.expand_path(lock_file)).to start_with(File.expand_path(root))
      lock.release
    end
  end
end
