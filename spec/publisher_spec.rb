require "spec_helper"
require "tmpdir"

RSpec.describe Textus::Ports::Publisher do
  let(:tmp) { Dir.mktmpdir }
  let(:store_root) { File.join(tmp, ".textus") }
  let(:src) { File.join(store_root, "zones", "output", "out.md") }
  let(:dst) { File.join(tmp, "dst.md") }
  let(:sentinel) { File.join(store_root, "sentinels", "dst.md.textus-managed.json") }

  before do
    FileUtils.mkdir_p(File.dirname(src))
    File.binwrite(src, "hello\n")
  end

  after { FileUtils.remove_entry(tmp) }

  it "copies source bytes verbatim to the target" do
    Textus::Ports::Publisher.publish(source: src, target: dst, store_root: store_root)
    expect(File.symlink?(dst)).to be false
    expect(File.binread(dst)).to eq(File.binread(src))
  end

  it "writes the sentinel under <store_root>/sentinels/ with repo-relative source/target fields" do
    Textus::Ports::Publisher.publish(source: src, target: dst, store_root: store_root)
    expect(File.exist?(sentinel)).to be true

    data = JSON.parse(File.read(sentinel))
    expect(data["source"]).to eq(".textus/zones/output/out.md")
    expect(data["target"]).to eq("dst.md")
    expect(data["sha256"]).to eq(Digest::SHA256.hexdigest(File.binread(dst)))
    expect(data["mode"]).to eq("copy")
  end

  it "mirrors nested target paths in the sentinel tree" do
    nested = File.join(tmp, ".claude-plugin", "marketplace.json")
    Textus::Ports::Publisher.publish(source: src, target: nested, store_root: store_root)
    expected_sentinel = File.join(store_root, "sentinels", ".claude-plugin", "marketplace.json.textus-managed.json")
    expect(File.exist?(expected_sentinel)).to be true
  end

  it "refuses to clobber an unmanaged file" do
    File.write(dst, "preexisting")
    expect { Textus::Ports::Publisher.publish(source: src, target: dst, store_root: store_root) }
      .to raise_error(Textus::PublishError, /clobber/)
  end

  it "overwrites when the target is already textus-managed (new-location sentinel)" do
    Textus::Ports::Publisher.publish(source: src, target: dst, store_root: store_root)
    File.binwrite(src, "world\n")
    Textus::Ports::Publisher.publish(source: src, target: dst, store_root: store_root)
    expect(File.binread(dst)).to eq("world\n")
  end

  it "creates parent directories that don't yet exist" do
    nested = File.join(tmp, "a", "b", "c", "out.md")
    Textus::Ports::Publisher.publish(source: src, target: nested, store_root: store_root)
    expect(File.binread(nested)).to eq(File.binread(src))
  end

  it "refuses to clobber an unmanaged symlink" do
    other = File.join(tmp, "other.md")
    File.binwrite(other, "preexisting\n")
    File.symlink(other, dst)
    expect { Textus::Ports::Publisher.publish(source: src, target: dst, store_root: store_root) }
      .to raise_error(Textus::PublishError, /clobber/)
  end

  describe ".unpublish" do
    it "deletes a managed target and its sentinel" do
      Dir.mktmpdir do |dir|
        store_root = File.join(dir, ".textus")
        FileUtils.mkdir_p(store_root)
        src = File.join(dir, "src.md")
        target = File.join(dir, "out.md")
        File.write(src, "hi\n")
        Textus::Ports::Publisher.publish(source: src, target: target, store_root: store_root)
        expect(File.exist?(target)).to be true

        Textus::Ports::Publisher.unpublish(target: target, store_root: store_root)
        expect(File.exist?(target)).to be false
        expect(File.exist?(Textus::Ports::SentinelStore.new.sentinel_path(target, store_root))).to be false
      end
    end

    it "is a no-op for an unmanaged file (no sentinel)" do
      Dir.mktmpdir do |dir|
        store_root = File.join(dir, ".textus")
        FileUtils.mkdir_p(store_root)
        target = File.join(dir, "human.md")
        File.write(target, "hand-written\n")

        Textus::Ports::Publisher.unpublish(target: target, store_root: store_root)
        expect(File.exist?(target)).to be true
      end
    end
  end
end
