require "spec_helper"
require "tmpdir"

RSpec.describe Textus::Infra::FileSystem do
  subject(:store) { described_class.new }

  let(:tmpdir) { Dir.mktmpdir }
  let(:path) { File.join(tmpdir, "test.txt") }

  after { FileUtils.rm_rf(tmpdir) }

  describe "#write" do
    it "writes bytes and creates parent directories" do
      nested = File.join(tmpdir, "a", "b", "test.txt")
      store.write(nested, "hello")
      expect(File.read(nested)).to eq("hello")
    end
  end

  describe "#read" do
    it "reads bytes from a file" do
      File.write(path, "world")
      expect(store.read(path)).to eq("world")
    end
  end

  describe "#delete" do
    it "deletes a file" do
      File.write(path, "x")
      store.delete(path)
      expect(File).not_to exist(path)
    end
  end

  describe "#exists?" do
    it "returns true for existing files" do
      File.write(path, "x")
      expect(store.exists?(path)).to be true
    end

    it "returns false for missing files" do
      expect(store.exists?(path)).to be false
    end
  end

  describe "#etag" do
    it "returns sha256:hexstring" do
      File.write(path, "content")
      expect(store.etag(path)).to match(/\Asha256:[a-f0-9]{64}\z/)
    end
  end

  describe "#size" do
    it "returns file size in bytes" do
      File.write(path, "12345")
      expect(store.size(path)).to eq(5)
    end
  end

  describe "#mkdir_p" do
    it "creates nested directories" do
      dir = File.join(tmpdir, "x", "y", "z")
      store.mkdir_p(dir)
      expect(File.directory?(dir)).to be true
    end
  end

  describe "#rmdir" do
    it "removes an empty directory" do
      dir = File.join(tmpdir, "empty")
      Dir.mkdir(dir)
      store.rmdir(dir)
      expect(File).not_to exist(dir)
    end
  end

  describe "#dir_empty?" do
    it "returns true for empty directories" do
      empty = File.join(tmpdir, "empty")
      Dir.mkdir(empty)
      expect(store.dir_empty?(empty)).to be true
    end

    it "returns false for non-empty directories" do
      File.write(path, "x")
      expect(store.dir_empty?(tmpdir)).to be false
    end
  end

  describe "#glob" do
    it "returns matching paths" do
      File.write(File.join(tmpdir, "a.txt"), "a")
      File.write(File.join(tmpdir, "b.txt"), "b")
      result = store.glob(File.join(tmpdir, "*.txt"))
      expect(result.size).to eq(2)
    end
  end

  describe "#mv" do
    it "renames a file" do
      File.write(path, "data")
      dest = File.join(tmpdir, "moved.txt")
      store.mv(path, dest)
      expect(File.read(dest)).to eq("data")
      expect(File).not_to exist(path)
    end
  end

  describe "#copy" do
    it "copies a file" do
      File.write(path, "data")
      dest = File.join(tmpdir, "copy.txt")
      store.copy(path, dest)
      expect(File.read(dest)).to eq("data")
      expect(File.read(path)).to eq("data")
    end
  end

  describe "#mtime" do
    it "returns modification time" do
      File.write(path, "x")
      expect(store.mtime(path)).to be_a(Time)
    end
  end

  describe "#directory?" do
    it "returns true for directories" do
      expect(store.directory?(tmpdir)).to be true
    end

    it "returns false for files" do
      File.write(path, "x")
      expect(store.directory?(path)).to be false
    end
  end

  describe "#symlink?" do
    it "returns false for regular files" do
      File.write(path, "x")
      expect(store.symlink?(path)).to be false
    end
  end

  describe "#identical?" do
    it "returns true for identical files" do
      a = File.join(tmpdir, "a.txt")
      b = File.join(tmpdir, "b.txt")
      File.write(a, "same")
      File.write(b, "same")
      expect(store.identical?(a, b)).to be true
    end
  end

  describe "#flock_exclusive" do
    it "acquires an exclusive lock and yields" do
      lockfile = File.join(tmpdir, "test.lock")
      yielded = false
      store.flock_exclusive(lockfile) { yielded = true }
      expect(yielded).to be true
    end

    # Cross-process lock contention is tested in spec/integration/port/build_lock_spec.rb
  end
end
