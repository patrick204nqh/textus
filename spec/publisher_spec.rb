require "spec_helper"
require "fileutils"
require "json"
require "tmpdir"

RSpec.describe Textus::Publisher do
  let(:tmp) { Dir.mktmpdir }
  let(:src) { File.join(tmp, "src.md") }
  let(:dst) { File.join(tmp, "dst.md") }
  let(:sentinel) { dst + ".textus-managed.json" }

  before { File.binwrite(src, "hello\n") }
  after  { FileUtils.remove_entry(tmp) }

  it "copies source bytes verbatim to the target" do
    Textus::Publisher.publish(source: src, target: dst)
    expect(File.symlink?(dst)).to be false
    expect(File.binread(dst)).to eq(File.binread(src))
  end

  it "writes a sentinel with source, sha256, and mode=copy" do
    Textus::Publisher.publish(source: src, target: dst)
    data = JSON.parse(File.read(sentinel))
    expect(data["source"]).to eq(src)
    expect(data["sha256"]).to eq(Digest::SHA256.hexdigest(File.binread(dst)))
    expect(data["mode"]).to eq("copy")
  end

  it "refuses to clobber an unmanaged file" do
    File.write(dst, "preexisting")
    expect { Textus::Publisher.publish(source: src, target: dst) }
      .to raise_error(Textus::PublishError, /clobber/)
  end

  it "overwrites when the target is already textus-managed" do
    Textus::Publisher.publish(source: src, target: dst)
    File.binwrite(src, "world\n")
    Textus::Publisher.publish(source: src, target: dst)
    expect(File.binread(dst)).to eq("world\n")
  end

  it "creates parent directories that don't yet exist" do
    nested = File.join(tmp, "a", "b", "c", "out.md")
    Textus::Publisher.publish(source: src, target: nested)
    expect(File.binread(nested)).to eq(File.binread(src))
    expect(File.exist?(nested + ".textus-managed.json")).to be true
  end

  it "replaces a managed legacy symlink at the target with a real copy" do
    other = File.join(tmp, "other.md")
    File.binwrite(other, "legacy\n")
    File.symlink(other, dst)
    File.write(sentinel, JSON.generate("source" => src, "sha256" => "x", "mode" => "symlink"))

    Textus::Publisher.publish(source: src, target: dst)

    expect(File.symlink?(dst)).to be false
    expect(File.binread(dst)).to eq(File.binread(src))
    expect(File.binread(other)).to eq("legacy\n")
  end

  it "refuses to clobber an unmanaged legacy symlink" do
    other = File.join(tmp, "other.md")
    File.binwrite(other, "legacy\n")
    File.symlink(other, dst)
    expect { Textus::Publisher.publish(source: src, target: dst) }
      .to raise_error(Textus::PublishError, /clobber/)
  end
end
