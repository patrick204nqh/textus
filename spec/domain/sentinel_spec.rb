require "spec_helper"
require "fileutils"
require "tmpdir"
require "json"
require "digest"

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

  describe Textus::Ports::SentinelStore do
    let(:store) { described_class.new }

    describe "#write!" do
      it "writes JSON with repo-relative target and source fields" do
        store.write!(target: dst_abs, source: src_abs, store_root: store_root)
        data = JSON.parse(File.read(sentinel_path))
        expect(data["target"]).to eq("dst.md")
        expect(data["source"]).to eq(".textus/zones/output/out.md")
        expect(data["sha256"]).to eq(Digest::SHA256.hexdigest("hello\n"))
        expect(data["mode"]).to eq("copy")
      end

      it "creates intermediate sentinel directories" do
        nested = File.join(tmp, "a", "b", "nested.md")
        FileUtils.mkdir_p(File.dirname(nested))
        File.binwrite(nested, "x")
        store.write!(target: nested, source: src_abs, store_root: store_root)
        expect(File.exist?(File.join(store_root, "sentinels", "a", "b", "nested.md.textus-managed.json"))).to be true
      end
    end

    describe "#load" do
      it "parses a repo-relative sentinel and resolves target/source to absolute" do
        store.write!(target: dst_abs, source: src_abs, store_root: store_root)
        s = store.load(sentinel_path, repo_root)
        expect(s.target).to eq(dst_abs)
        expect(s.source).to eq(src_abs)
        expect(s.sha256).to eq(Digest::SHA256.hexdigest("hello\n"))
        expect(s.mode).to eq("copy")
      end

      it "accepts a legacy absolute-path sentinel without re-rooting" do
        FileUtils.mkdir_p(File.dirname(sentinel_path))
        File.write(sentinel_path, JSON.generate(
                                    "source" => src_abs,
                                    "target" => dst_abs,
                                    "sha256" => Digest::SHA256.hexdigest("hello\n"),
                                    "mode" => "copy",
                                  ))
        s = store.load(sentinel_path, repo_root)
        expect(s.target).to eq(dst_abs)
        expect(s.source).to eq(src_abs)
      end

      it "returns nil on invalid JSON" do
        FileUtils.mkdir_p(File.dirname(sentinel_path))
        File.write(sentinel_path, "{not json")
        expect(store.load(sentinel_path, repo_root)).to be_nil
      end

      it "returns nil when the sentinel file is missing" do
        expect(store.load(File.join(tmp, "does-not-exist.json"), repo_root)).to be_nil
      end
    end

    describe "#sentinel_path" do
      it "places sentinel under <store_root>/sentinels/ mirroring repo-relative target" do
        expect(store.sentinel_path(dst_abs, store_root))
          .to eq(File.join(store_root, "sentinels", "dst.md.textus-managed.json"))
      end
    end
  end
end
