require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe Textus::Migration::V3::ZoneRenamer do
  let(:tmpdir) { Dir.mktmpdir }
  let(:zones_dir) { File.join(tmpdir, ".textus/zones") }

  after { FileUtils.rm_rf(tmpdir) }

  def make_inbox(*files)
    inbox = File.join(zones_dir, "inbox")
    FileUtils.mkdir_p(inbox)
    files.each do |f|
      FileUtils.touch(File.join(inbox, f))
    end
    inbox
  end

  def make_intake
    intake = File.join(zones_dir, "intake")
    FileUtils.mkdir_p(intake)
    intake
  end

  it "renames inbox/ to intake/ and preserves files inside" do
    make_inbox("note.md", "other.txt")
    described_class.run(root: tmpdir)

    expect(Dir.exist?(File.join(zones_dir, "intake"))).to be true
    expect(Dir.exist?(File.join(zones_dir, "inbox"))).to be false
    expect(File.exist?(File.join(zones_dir, "intake/note.md"))).to be true
    expect(File.exist?(File.join(zones_dir, "intake/other.txt"))).to be true
  end

  it "is a no-op when inbox/ does not exist" do
    make_intake
    expect { described_class.run(root: tmpdir) }.not_to raise_error
    expect(Dir.exist?(File.join(zones_dir, "intake"))).to be true
  end

  it "is a no-op when neither inbox/ nor intake/ exists" do
    FileUtils.mkdir_p(zones_dir)
    expect { described_class.run(root: tmpdir) }.not_to raise_error
  end

  it "raises when both inbox/ and intake/ exist" do
    make_inbox
    make_intake
    expect { described_class.run(root: tmpdir) }
      .to raise_error(/Refusing to migrate/)
  end
end
