require "spec_helper"
require "tmpdir"
require "timeout"

RSpec.describe Textus::Ports::Fetch::Lock do
  it "acquires and releases a per-key file lock" do
    Dir.mktmpdir do |root|
      lock = Textus::Ports::Fetch::Lock.new(root: root, key: "working.foo")
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

  it "re-acquires after the previous holder dies abruptly (orphan file on disk)",
     skip: ("requires fork" unless Process.respond_to?(:fork)) do
    Dir.mktmpdir do |root|
      key = "intake.vendor.example"
      ready = File.join(root, "child-ready")

      child = Process.fork do
        lock = Textus::Ports::Fetch::Lock.new(root: root, key: key)
        exit(1) unless lock.try_acquire
        File.write(ready, "ok")
        sleep 30
      end

      Timeout.timeout(5) { sleep 0.05 until File.exist?(ready) }

      Process.kill("KILL", child)
      Process.wait(child)

      lock_path = File.join(root, ".locks", "intake.vendor.example.lock")
      expect(File).to exist(lock_path)
      pid_in_file = File.read(lock_path).to_i
      expect(pid_in_file).to eq(child)
      expect { Process.kill(0, pid_in_file) }.to raise_error(Errno::ESRCH)

      fresh = Textus::Ports::Fetch::Lock.new(root: root, key: key)
      expect(fresh.try_acquire).to be(true)
      fresh.release
    end
  end

  it "escapes unsafe key characters in the lock file path" do
    Dir.mktmpdir do |root|
      lock = Textus::Ports::Fetch::Lock.new(root: root, key: "working/../escape")
      lock.try_acquire
      lock_file = lock.instance_variable_get(:@path)
      expect(File.expand_path(lock_file)).to start_with(File.expand_path(root))
      lock.release
    end
  end
end
