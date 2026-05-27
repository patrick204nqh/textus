require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Textus::Doctor::Check::ProtocolVersion do
  let(:tmp) { Dir.mktmpdir }

  after { FileUtils.remove_entry(tmp) }

  it "returns no issues when manifest is missing (doctor handles that elsewhere)" do
    expect(described_class.run(root: tmp)).to be_empty
  end

  it "returns no issues when manifest version is textus/3" do
    FileUtils.mkdir_p(File.join(tmp, ".textus"))
    File.write(File.join(tmp, ".textus/manifest.yaml"), "version: textus/3\nzones: []\nentries: []\n")
    expect(described_class.run(root: tmp)).to be_empty
  end

  it "returns a protocol_mismatch issue when version is not textus/3" do
    FileUtils.mkdir_p(File.join(tmp, ".textus"))
    File.write(File.join(tmp, ".textus/manifest.yaml"), "version: textus/4\nzones: []\nentries: []\n")
    issues = described_class.run(root: tmp)
    expect(issues.first["code"]).to eq("protocol_mismatch")
    expect(issues.first["severity"]).to eq("error")
  end
end
