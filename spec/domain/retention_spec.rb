require "spec_helper"

RSpec.describe Textus::Domain::Retention do
  include_context "textus_store_fixture"

  def write_manifest
    store_from_manifest(root, zones: %w[proposals], manifest: <<~YAML)
      version: textus/3
      roles:
        - { name: human, can: [author, propose] }
        - { name: agent, can: [propose] }
      zones:
        - { name: proposals, kind: queue }
      entries:
        - { key: proposals.notes, path: proposals/notes, zone: proposals, owner: agent:self, kind: nested }
      rules:
        - match: proposals.**
          retention: { expire_after: 1d }
    YAML
    FileUtils.mkdir_p(File.join(root, "zones", "proposals", "notes"))
  end

  def write_leaf(name, mtime)
    path = File.join(root, "zones", "proposals", "notes", "#{name}.md")
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

    expect(rows.map { |r| r["key"] }).to eq(["proposals.notes.old"])
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
