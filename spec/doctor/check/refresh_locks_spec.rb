require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Textus::Doctor::Check::RefreshLocks do
  def with_store
    Dir.mktmpdir do |root|
      textus = File.join(root, ".textus")
      FileUtils.mkdir_p(File.join(textus, "zones", "working"))
      File.write(File.join(textus, "manifest.yaml"), <<~YAML)
        version: textus/3
        zones:
          - { name: working, kind: origin }
        entries: []
      YAML
      yield Textus::Store.new(textus), textus
    end
  end

  it "returns no issues when .locks/ does not exist" do
    with_store do |store, _|
      expect(described_class.new(store.container).call).to eq([])
    end
  end

  it "returns no issues when lock file's PID is alive" do
    with_store do |store, root|
      locks = File.join(root, ".locks")
      FileUtils.mkdir_p(locks)
      File.write(File.join(locks, "intake.vendor.foo.lock"), Process.pid.to_s)

      expect(described_class.new(store.container).call).to eq([])
    end
  end

  it "reports an info-level issue when lock file records a dead PID" do
    with_store do |store, root|
      locks = File.join(root, ".locks")
      FileUtils.mkdir_p(locks)
      dead_pid = find_dead_pid
      lock_path = File.join(locks, "intake.vendor.foo.lock")
      File.write(lock_path, dead_pid.to_s)

      issues = described_class.new(store.container).call
      expect(issues.length).to eq(1)
      expect(issues.first).to include(
        "code" => "refresh_lock.stale",
        "level" => "info",
        "subject" => lock_path,
      )
      expect(issues.first["message"]).to include(dead_pid.to_s)
      expect(issues.first["fix"]).to include("rm #{lock_path}")
    end
  end

  it "ignores empty or zero-PID files" do
    with_store do |store, root|
      locks = File.join(root, ".locks")
      FileUtils.mkdir_p(locks)
      File.write(File.join(locks, "empty.lock"), "")
      File.write(File.join(locks, "zero.lock"), "0")

      expect(described_class.new(store.container).call).to eq([])
    end
  end

  # Find a PID that is guaranteed to be dead: fork, wait, return the now-reaped PID.
  def find_dead_pid
    pid = Process.fork { exit(0) }
    Process.wait(pid)
    pid
  end
end
