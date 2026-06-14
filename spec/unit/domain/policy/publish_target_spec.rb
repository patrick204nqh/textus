require "spec_helper"

RSpec.describe Textus::Manifest::Policy::PublishTarget do
  it "parses a to-target with a template + inject_boot" do
    t = described_class.new("to" => "CLAUDE.md", "template" => "c.mustache", "inject_boot" => true)
    expect(t.to_target?).to be(true)
    expect(t.tree_target?).to be(false)
    expect(t.renders?).to be(true)
    expect(t.template).to eq("c.mustache")
    expect(t.inject_boot).to be(true)
  end

  it "parses a verbatim to-target (no template => copy)" do
    t = described_class.new("to" => ".mcp.json")
    expect(t.renders?).to be(false)
    expect(t.inject_boot).to be(false)
  end

  it "parses a tree-target" do
    t = described_class.new("tree" => "skills/")
    expect(t.tree_target?).to be(true)
    expect(t.to_target?).to be(false)
    expect(t.tree).to eq("skills/")
    expect(t.renders?).to be(false)
  end

  it "rejects a target with neither to nor tree" do
    expect { described_class.new("template" => "c") }
      .to raise_error(Textus::BadManifest, /exactly one of `to:` or `tree:`/)
  end

  it "rejects a target with both to and tree" do
    expect { described_class.new("to" => "a", "tree" => "b") }
      .to raise_error(Textus::BadManifest, /exactly one of `to:` or `tree:`/)
  end

  it "rejects render flags on a tree-target" do
    expect { described_class.new("tree" => "d", "template" => "t") }
      .to raise_error(Textus::BadManifest, /tree target takes no/)
  end

  it "rejects a removed provenance flag" do
    expect { described_class.new("to" => "x", "provenance" => false) }
      .to raise_error(Textus::BadManifest, /provenance.*_meta|removed/)
  end
end
