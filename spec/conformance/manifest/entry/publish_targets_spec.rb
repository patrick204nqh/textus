# spec/unit/manifest/entry/publish_targets_spec.rb
require "spec_helper"

RSpec.describe "publish: list parsing (ADR 0094)" do
  def parse(raw) = Textus::Manifest::Entry::Parser.call(raw)

  let(:base) do
    { "key" => "feeds.cat", "path" => "feeds/cat.json", "zone" => "feeds", "kind" => "produced",
      "source" => { "from" => "project", "select" => ["k.*"] } }
  end

  it "builds PublishTarget objects from a list" do
    e = parse(base.merge("publish" => [
                           { "to" => "CLAUDE.md", "template" => "c.mustache", "inject_boot" => true },
                           { "to" => ".mcp.json" },
                         ]))
    expect(e.publish_targets.map(&:to)).to eq(["CLAUDE.md", ".mcp.json"])
    expect(e.publish_targets.first.renders?).to be(true)
  end

  it "derives publish_to (to-targets) and publish_tree from the single state" do
    e = parse(base.merge("publish" => [{ "to" => "a" }, { "to" => "b" }]))
    expect(e.publish_to).to eq(%w[a b])
    expect(e.publish_tree).to be_nil
    t = parse(base.merge("publish" => [{ "tree" => "skills/" }]))
    expect(t.publish_tree).to eq("skills/")
    expect(t.publish_to).to eq([])
  end

  it "defaults to no targets when publish: is absent" do
    expect(parse(base).publish_targets).to eq([])
  end

  it "rejects the retired publish: { to: [...] } map form" do
    expect { parse(base.merge("publish" => { "to" => %w[a b] })) }
      .to raise_error(Textus::BadManifest, /list of targets|ADR 0094/)
  end

  it "rejects the retired publish: { tree: ... } map form" do
    expect { parse(base.merge("publish" => { "tree" => "d" })) }
      .to raise_error(Textus::BadManifest, /list of targets|ADR 0094/)
  end
end
