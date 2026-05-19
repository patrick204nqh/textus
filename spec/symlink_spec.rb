require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe Textus::Symlink do
  let(:tmp) { Dir.mktmpdir }
  let(:src) { File.join(tmp, "src.md") }
  let(:dst) { File.join(tmp, "dst.md") }

  before { File.write(src, "hello") }
  after  { FileUtils.remove_entry(tmp) }

  it "creates a symlink from dst to src" do
    Textus::Symlink.publish(source: src, target: dst)
    expect(File.symlink?(dst)).to be true
    expect(File.read(dst)).to eq("hello")
  end

  it "replaces an existing symlink" do
    File.symlink("/tmp/somewhere-else", dst)
    Textus::Symlink.publish(source: src, target: dst)
    expect(File.readlink(dst)).to eq(src)
  end

  it "refuses to clobber a non-symlink file" do
    File.write(dst, "preexisting")
    expect { Textus::Symlink.publish(source: src, target: dst) }
      .to raise_error(Textus::PublishError, /clobber/)
  end

  it "falls back to copy + sentinel when symlink unsupported" do
    allow(File).to receive(:symlink).and_raise(NotImplementedError)
    Textus::Symlink.publish(source: src, target: dst)
    expect(File.read(dst)).to eq("hello")
    expect(File.exist?(dst + ".textus-managed.json")).to be true
  end
end
