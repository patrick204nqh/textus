require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe Textus::Role do
  let(:tmp) { Dir.mktmpdir("textus-role") }
  let(:root) { File.join(tmp, ".textus") }

  before { FileUtils.mkdir_p(root) }
  after  { FileUtils.remove_entry(tmp) if File.directory?(tmp) }

  it "uses --as flag if given" do
    expect(Textus::Role.resolve(flag: "agent", env: {}, root: root)).to eq("agent")
  end

  it "falls back to TEXTUS_ROLE env" do
    expect(Textus::Role.resolve(flag: nil, env: { "TEXTUS_ROLE" => "runner" }, root: root)).to eq("runner")
  end

  it "falls back to .textus/role file" do
    File.write(File.join(root, "role"), "agent\n")
    expect(Textus::Role.resolve(flag: nil, env: {}, root: root)).to eq("agent")
  end

  it "defaults to human" do
    expect(Textus::Role.resolve(flag: nil, env: {}, root: root)).to eq("human")
  end

  it "rejects invalid characters" do
    expect { Textus::Role.resolve(flag: "AI!", env: {}, root: root) }
      .to raise_error(Textus::InvalidRole)
  end
end
