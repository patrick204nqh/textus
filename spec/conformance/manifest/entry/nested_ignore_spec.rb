require "spec_helper"

RSpec.describe "Textus::Manifest::Entry::Nested ignore parsing" do
  def nested(raw)
    common = {
      raw: raw, key: raw["key"], path: raw["path"], lane: raw["lane"],
      schema: nil, owner: "human:self", format: "markdown", publish_targets: []
    }
    Textus::Manifest::Entry::Nested.from_raw(common, raw)
  end

  let(:base_raw) do
    { "key" => "skills", "path" => "skills", "lane" => "knowledge",
      "kind" => "nested", "nested" => true }
  end

  it "defaults ignore to an empty list" do
    expect(nested(base_raw).ignore).to eq([])
  end

  it "parses an ignore list" do
    entry = nested(base_raw.merge("ignore" => ["**/node_modules/**"]))
    expect(entry.ignore).to eq(["**/node_modules/**"])
  end

  it "ignored? is true for a matching relative path" do
    entry = nested(base_raw.merge("ignore" => ["**/node_modules/**"]))
    expect(entry.ignored?("node_modules/dep/SKILL.md")).to be(true)
  end

  it "ignored? is false with no patterns" do
    expect(nested(base_raw).ignored?("node_modules/dep/SKILL.md")).to be(false)
  end

  it "Base entries report ignored? false" do
    raw = { "key" => "n", "path" => "notes.md", "lane" => "working", "kind" => "leaf" }
    common = { raw: raw, key: "n", path: "notes.md", lane: "working",
               schema: nil, owner: "human:self", format: "markdown", publish_targets: [] }
    leaf = Textus::Manifest::Entry::Leaf.from_raw(common, raw)
    expect(leaf.ignored?("anything/SKILL.md")).to be(false)
  end
end
