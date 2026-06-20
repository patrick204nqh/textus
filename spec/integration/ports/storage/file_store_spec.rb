require "spec_helper"

RSpec.describe Textus::Port::Storage::FileStore do
  subject(:store) { described_class.new }

  let(:tmp)  { Dir.mktmpdir("textus-file-store") }
  let(:path) { File.join(tmp, "nested", "deeper", "file.bin") }

  after { FileUtils.remove_entry(tmp) if File.directory?(tmp) }

  describe "#write / #read" do
    it "round-trips bytes binary-exactly" do
      bytes = "hello \xFF\x00 world".b
      store.write(path, bytes)
      expect(store.read(path)).to eq(bytes)
      expect(store.read(path).encoding).to eq(Encoding::ASCII_8BIT)
    end

    it "creates parent directories on write" do
      expect(File.directory?(File.dirname(path))).to be(false)
      store.write(path, "x")
      expect(File.directory?(File.dirname(path))).to be(true)
    end
  end

  describe "#delete" do
    it "removes the file" do
      store.write(path, "x")
      store.delete(path)
      expect(File.exist?(path)).to be(false)
    end

    it "raises Errno::ENOENT when the file is absent" do
      expect { store.delete(path) }.to raise_error(Errno::ENOENT)
    end
  end

  describe "#exists?" do
    it "returns false before write and true after" do
      expect(store.exists?(path)).to be(false)
      store.write(path, "x")
      expect(store.exists?(path)).to be(true)
    end

    it "agrees with File.exist? after write" do
      store.write(path, "x")
      expect(store.exists?(path)).to eq(File.exist?(path))
    end
  end

  describe "#etag" do
    it "is stable across reads of the same bytes" do
      store.write(path, "abc")
      first = store.etag(path)
      second = store.etag(path)
      expect(first).to eq(second)
    end

    it "differs across changes" do
      store.write(path, "abc")
      before = store.etag(path)
      store.write(path, "abcd")
      expect(store.etag(path)).not_to eq(before)
    end

    it "matches Etag.for_file" do
      store.write(path, "abc")
      expect(store.etag(path)).to eq(Textus::Value::Etag.for_file(path))
    end
  end
end
