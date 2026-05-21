require "spec_helper"
require "fileutils"
require "tmpdir"
require "json"
require "stringio"

RSpec.describe Textus::MigrateV2 do
  let(:tmp)  { Dir.mktmpdir }
  let(:root) { File.join(tmp, ".textus") }

  after { FileUtils.remove_entry(tmp) }

  def write_manifest(version)
    FileUtils.mkdir_p(root)
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: #{version}
      entries: []
    YAML
  end

  it "upgrades textus/1 → textus/2 in the manifest file" do
    write_manifest("textus/1")
    res = described_class.run(root)
    expect(res["ok"]).to be true
    expect(res["from"]).to eq("textus/1")
    expect(res["to"]).to eq("textus/2")
    expect(File.read(File.join(root, "manifest.yaml"))).to include("version: textus/2")
    expect(File.read(File.join(root, "manifest.yaml"))).not_to include("textus/1")
  end

  it "is a no-op when already textus/2" do
    write_manifest("textus/2")
    res = described_class.run(root)
    expect(res["ok"]).to be true
    expect(res["no_op"]).to be true
  end

  it "raises UsageError for unknown version strings" do
    write_manifest("textus/99")
    expect { described_class.run(root) }.to raise_error(Textus::UsageError, /cannot migrate/)
  end

  it "raises IoError when manifest is missing" do
    FileUtils.mkdir_p(root)
    expect { described_class.run(root) }.to raise_error(Textus::IoError, /manifest not found/)
  end

  describe "via CLI" do
    it "migrates a textus/1 manifest via the CLI" do
      FileUtils.mkdir_p(root)
      File.write(File.join(root, "manifest.yaml"), "version: textus/1\nentries: []\n")

      out = StringIO.new
      rc = Textus::CLI.run(
        ["migrate", "v2", "--format=json"],
        stdin: StringIO.new, stdout: out, stderr: StringIO.new, cwd: tmp,
      )
      expect(rc).to eq(0)
      payload = JSON.parse(out.string.lines.last)
      expect(payload["ok"]).to be true
      expect(payload["to"]).to eq("textus/2")
    end

    it "returns usage error for missing target" do
      FileUtils.mkdir_p(root)
      File.write(File.join(root, "manifest.yaml"), "version: textus/2\nentries: []\n")

      out = StringIO.new
      rc = Textus::CLI.run(
        ["migrate", "--format=json"],
        stdin: StringIO.new, stdout: out, stderr: StringIO.new, cwd: tmp,
      )
      expect(rc).not_to eq(0)
    end
  end
end
