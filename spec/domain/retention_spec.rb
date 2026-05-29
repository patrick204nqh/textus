require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe Textus::Domain::Retention do
  let(:tmp)  { Dir.mktmpdir }
  let(:root) { File.join(tmp, ".textus") }

  def write_manifest
    FileUtils.mkdir_p(File.join(root, "zones", "review", "notes"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      roles:
        - { name: human, kind: accept_authority }
        - { name: agent, kind: proposer }
      zones:
        - { name: review, kind: queue, write_policy: [agent, human] }
      entries:
        - { key: review.notes, path: review/notes, zone: review, schema: null, owner: agent:self, nested: true, kind: nested }
      rules:
        - match: review.**
          retention: { expire_after: 1d }
    YAML
  end

  def write_leaf(name, mtime)
    path = File.join(root, "zones", "review", "notes", "#{name}.md")
    File.write(path, "---\nname: #{name}\n---\nbody\n")
    File.utime(mtime, mtime, path)
    path
  end

  it "reports :expire for a leaf older than expire_after" do
    write_manifest
    write_leaf("old", Time.now - (2 * 86_400))
    manifest = Textus::Manifest.load(root)

    clock = Class.new { def self.now = Time.now }
    rows = described_class.new(
      manifest: manifest,
      file_stat: Textus::Ports::Storage::FileStat.new,
      clock: clock,
    ).call

    expect(rows.map { |r| r["key"] }).to eq(["review.notes.old"])
    expect(rows.first["action"]).to eq("expire")
  end

  it "reports nothing for a fresh leaf" do
    write_manifest
    write_leaf("fresh", Time.now)
    manifest = Textus::Manifest.load(root)
    rows = described_class.new(
      manifest: manifest, file_stat: Textus::Ports::Storage::FileStat.new, clock: Time,
    ).call
    expect(rows).to be_empty
  end
end
