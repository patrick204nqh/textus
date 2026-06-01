require "spec_helper"

RSpec.describe Textus::Role do
  let(:tmp) { Dir.mktmpdir("textus-role") }
  let(:root) { File.join(tmp, ".textus") }

  before { FileUtils.mkdir_p(root) }
  after  { FileUtils.remove_entry(tmp) if File.directory?(tmp) }

  it "uses --as flag if given" do
    expect(Textus::Role.resolve(flag: "agent", env: {}, root: root)).to eq("agent")
  end

  it "falls back to TEXTUS_ROLE env" do
    expect(Textus::Role.resolve(flag: nil, env: { "TEXTUS_ROLE" => "automation" }, root: root)).to eq("automation")
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

  it "rejects a syntactically valid name outside the closed set (ADR 0045)" do
    expect { Textus::Role.resolve(flag: "compiler", env: {}, root: root) }
      .to raise_error(Textus::InvalidRole)
  end

  it "falls back to the supplied default when no flag/env/file resolves" do
    expect(Textus::Role.resolve(flag: nil, env: {}, root: root, default: "agent")).to eq("agent")
  end

  it "prefers env over the supplied default" do
    expect(Textus::Role.resolve(flag: nil, env: { "TEXTUS_ROLE" => "human" }, root: root, default: "agent"))
      .to eq("human")
  end

  it "exposes the MCP transport default constant" do
    expect(Textus::Role::AGENT).to eq("agent")
  end

  it "builds the closed name set from the archetype constants (ADR 0045)" do
    expect(Textus::Role::NAMES).to eq(%w[human agent automation])
    expect(Textus::Role::NAMES).to include(Textus::Role::DEFAULT, Textus::Role::AGENT)
    expect(Textus::Role::DEFAULT).to eq(Textus::Role::HUMAN)
  end
end
