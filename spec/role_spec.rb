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
    expect(Textus::Role::AGENT).to match(Textus::Role::PATTERN)
  end

  it "builds the closed name set from the archetype constants (ADR 0045)" do
    expect(Textus::Role::NAMES).to eq(%w[human agent automation])
    expect(Textus::Role::NAMES).to include(Textus::Role::DEFAULT, Textus::Role::AGENT)
    expect(Textus::Role::DEFAULT).to eq(Textus::Role::HUMAN)
  end

  describe ".valid_owner?" do
    it "accepts a bare archetype (the shipped `owner: agent` zone form)" do
      expect(Textus::Role.valid_owner?("agent")).to be(true)
      expect(Textus::Role.valid_owner?("human")).to be(true)
      expect(Textus::Role.valid_owner?("automation")).to be(true)
    end

    it "accepts <archetype>:<subject>" do
      expect(Textus::Role.valid_owner?("human:patrick")).to be(true)
      expect(Textus::Role.valid_owner?("agent:self")).to be(true)
      expect(Textus::Role.valid_owner?("automation:ci")).to be(true)
    end

    it "rejects an archetype outside the closed set" do
      expect(Textus::Role.valid_owner?("compiler:whoever")).to be(false)
      expect(Textus::Role.valid_owner?("garbage")).to be(false)
    end

    it "rejects an empty subject" do
      expect(Textus::Role.valid_owner?("human:")).to be(false)
    end

    it "rejects a subject containing a colon (PATTERN excludes ':')" do
      expect(Textus::Role.valid_owner?("human:a:b")).to be(false)
    end

    it "rejects non-strings and the empty string" do
      expect(Textus::Role.valid_owner?(nil)).to be(false)
      expect(Textus::Role.valid_owner?("")).to be(false)
      expect(Textus::Role.valid_owner?(42)).to be(false)
    end
  end
end
