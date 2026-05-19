require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe Textus::Role do
  let(:tmp) { Dir.mktmpdir("textus-role") }
  let(:root) { File.join(tmp, ".textus") }

  before { FileUtils.mkdir_p(root) }
  after  { FileUtils.remove_entry(tmp) if File.directory?(tmp) }

  it "uses --as flag if given" do
    expect(Textus::Role.resolve(flag: "ai", env: {}, root: root)).to eq("ai")
  end

  it "falls back to TEXTUS_ROLE env" do
    expect(Textus::Role.resolve(flag: nil, env: { "TEXTUS_ROLE" => "script" }, root: root)).to eq("script")
  end

  it "falls back to .textus/role file" do
    File.write(File.join(root, "role"), "ai\n")
    expect(Textus::Role.resolve(flag: nil, env: {}, root: root)).to eq("ai")
  end

  it "defaults to human" do
    expect(Textus::Role.resolve(flag: nil, env: {}, root: root)).to eq("human")
  end

  it "rejects invalid characters" do
    expect { Textus::Role.resolve(flag: "AI!", env: {}, root: root) }
      .to raise_error(Textus::InvalidRole)
  end
end
