require "spec_helper"

RSpec.describe Textus::Domain::Sentinel do
  let(:tmp)        { Dir.mktmpdir("textus-sentinel") }
  let(:repo_root)  { tmp }
  let(:store_root) { File.join(tmp, ".textus") }
  let(:src_abs)    { File.join(store_root, "zones", "output", "out.md") }
  let(:dst_abs)    { File.join(tmp, "dst.md") }
  let(:sentinel_path) do
    File.join(store_root, "sentinels", "dst.md.textus-managed.json")
  end
  let(:store)     { Textus::Ports::SentinelStore.new }
  let(:file_stat) { Textus::Ports::Storage::FileStat.new }

  before do
    FileUtils.mkdir_p(File.dirname(src_abs))
    File.binwrite(src_abs, "hello\n")
    FileUtils.mkdir_p(File.dirname(dst_abs))
    File.binwrite(dst_abs, "hello\n")
  end

  after { FileUtils.remove_entry(tmp) if File.directory?(tmp) }

  describe "pure value attributes" do
    it "exposes target, source, sha256, mode" do
      s = described_class.new(target: dst_abs, source: src_abs, sha256: "abc", mode: "copy")
      expect(s.target).to eq(dst_abs)
      expect(s.source).to eq(src_abs)
      expect(s.sha256).to eq("abc")
      expect(s.mode).to eq("copy")
    end
  end

  describe "#orphan? / #drift?" do
    it "reports orphan when target file is missing" do
      store.write!(target: dst_abs, source: src_abs, store_root: store_root)
      File.delete(dst_abs)
      s = store.load(sentinel_path, repo_root)
      expect(s.orphan?(file_stat)).to be true
      expect(s.drift?(file_stat)).to be false
    end

    it "reports drift when target bytes diverge from recorded sha256" do
      store.write!(target: dst_abs, source: src_abs, store_root: store_root)
      File.binwrite(dst_abs, "tampered\n")
      s = store.load(sentinel_path, repo_root)
      expect(s.orphan?(file_stat)).to be false
      expect(s.drift?(file_stat)).to be true
    end

    it "reports neither when target matches recorded sha256" do
      store.write!(target: dst_abs, source: src_abs, store_root: store_root)
      s = store.load(sentinel_path, repo_root)
      expect(s.orphan?(file_stat)).to be false
      expect(s.drift?(file_stat)).to be false
    end

    it "reports orphan when target is nil" do
      s = described_class.new(target: nil, source: src_abs, sha256: "abc", mode: "copy")
      expect(s.orphan?(file_stat)).to be true
    end

    it "reports no drift when sha256 is nil" do
      s = described_class.new(target: dst_abs, source: src_abs, sha256: nil, mode: "copy")
      expect(s.drift?(file_stat)).to be false
    end
  end
end
