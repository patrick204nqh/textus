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

  # rubocop:disable RSpec/ExampleLength
  it "raises BuildInProgress when another process holds the lock" do
    parent_read, child_write = IO.pipe
    child_read, parent_write = IO.pipe

    pid = fork do
      parent_read.close
      parent_write.close
      described_class.with(root: root) do
        child_write.puts("locked")
        child_write.flush
        child_read.gets # wait for parent to attempt
      end
    end

    child_write.close
    child_read.close
    parent_read.gets # wait for child to acquire

    expect do
      described_class.with(root: root) { :noop }
    end.to raise_error(Textus::BuildInProgress) do |err|
      expect(err.exit_code).to eq(75)
      expect(err.details["holder"]).to match(/pid=#{pid}\b/)
    end

    parent_write.puts("release")
    parent_write.flush
    Process.wait(pid)
  ensure
    [parent_read, parent_write, child_read, child_write].each do |io|
      begin
        io.close
      rescue StandardError
        nil
      end
    end
  end
  # rubocop:enable RSpec/ExampleLength

  it "auto-releases when the holding process dies (kernel releases FD)" do
    parent_read, child_write = IO.pipe

    pid = fork do
      parent_read.close
      # rubocop:disable Style/FileOpen
      # Intentionally leak the FD: the child sleeps until SIGKILL, and the
      # kernel releases the flock when the process dies. A block form would
      # close the FD (and release the lock) before SIGKILL arrives.
      file = File.open(File.join(root, described_class::LOCK_FILENAME), File::RDWR | File::CREAT, 0o644)
      # rubocop:enable Style/FileOpen
      file.flock(File::LOCK_EX | File::LOCK_NB) or exit!(1)
      child_write.puts("locked")
      child_write.flush
      sleep 30 # hold until SIGKILL
    end

    child_write.close
    parent_read.gets # wait for child to acquire

    Process.kill("KILL", pid)
    Process.wait(pid)

    expect { described_class.with(root: root) { :noop } }.not_to raise_error
  ensure
    [parent_read, child_write].each do |io|
      begin
        io.close
      rescue StandardError
        nil
      end
    end
  end
end
