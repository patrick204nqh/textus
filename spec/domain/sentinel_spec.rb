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

  before do
    FileUtils.mkdir_p(File.dirname(src_abs))
    File.binwrite(src_abs, "hello\n")
    FileUtils.mkdir_p(File.dirname(dst_abs))
    File.binwrite(dst_abs, "hello\n")
  end

  after { FileUtils.remove_entry(tmp) if File.directory?(tmp) }

  describe ".write!" do
    it "writes JSON with repo-relative target and source fields" do
      described_class.write!(target: dst_abs, source: src_abs, store_root: store_root)
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
      described_class.write!(target: nested, source: src_abs, store_root: store_root)
      expect(File.exist?(File.join(store_root, "sentinels", "a", "b", "nested.md.textus-managed.json"))).to be true
    end
  end

  describe ".load" do
    it "parses a repo-relative sentinel and resolves target/source to absolute" do
      described_class.write!(target: dst_abs, source: src_abs, store_root: store_root)
      s = described_class.load(sentinel_path, repo_root)
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
      s = described_class.load(sentinel_path, repo_root)
      expect(s.target).to eq(dst_abs)
      expect(s.source).to eq(src_abs)
    end

    it "returns nil on invalid JSON" do
      FileUtils.mkdir_p(File.dirname(sentinel_path))
      File.write(sentinel_path, "{not json")
      expect(described_class.load(sentinel_path, repo_root)).to be_nil
    end

    it "returns nil when the sentinel file is missing" do
      expect(described_class.load(File.join(tmp, "does-not-exist.json"), repo_root)).to be_nil
    end
  end

  describe "#orphan? / #drift?" do
    it "reports orphan when target file is missing" do
      described_class.write!(target: dst_abs, source: src_abs, store_root: store_root)
      File.delete(dst_abs)
      s = described_class.load(sentinel_path, repo_root)
      expect(s.orphan?).to be true
      expect(s.drift?).to be false
    end

    it "reports drift when target bytes diverge from recorded sha256" do
      described_class.write!(target: dst_abs, source: src_abs, store_root: store_root)
      File.binwrite(dst_abs, "tampered\n")
      s = described_class.load(sentinel_path, repo_root)
      expect(s.orphan?).to be false
      expect(s.drift?).to be true
    end

    it "reports neither when target matches recorded sha256" do
      described_class.write!(target: dst_abs, source: src_abs, store_root: store_root)
      s = described_class.load(sentinel_path, repo_root)
      expect(s.orphan?).to be false
      expect(s.drift?).to be false
    end
  end
end
