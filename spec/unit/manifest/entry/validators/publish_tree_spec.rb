require "spec_helper"

# ADR 0049: publish_tree shape rules moved onto Publish::Tree and exclusivity
# moved into Publish.resolve; both are reached through Validators::Publish.
# ADR 0094: publish config is a LIST of targets — a tree-target is [{ tree: }].
RSpec.describe Textus::Manifest::Entry::Validators::Publish do
  def entry(raw)
    common = {
      raw: raw, key: raw["key"], path: raw["path"], zone: raw["zone"],
      schema: nil, owner: nil, format: "markdown",
      publish_targets: Array(raw["publish"]).map { |t| Textus::Domain::Policy::PublishTarget.new(t) }
    }
    Textus::Manifest::Entry::Nested.from_raw(common, raw)
  end

  def validate(raw) = described_class.call(entry(raw), policy: nil)

  let(:base) do
    { "key" => "working.skills", "path" => "working/skills", "zone" => "working", "nested" => true }
  end

  it "passes a well-formed publish.tree entry" do
    expect { validate(base.merge("publish" => [{ "tree" => "skills" }])) }.not_to raise_error
  end

  it "passes when no publish block is set (resolves to None)" do
    expect { validate(base) }.not_to raise_error
  end

  it "rejects publish.tree on a non-nested entry" do
    common = { raw: { "publish" => [{ "tree" => "x" }] }, key: "k", path: "p", zone: "working",
               schema: nil, owner: nil, format: "markdown",
               publish_targets: [Textus::Domain::Policy::PublishTarget.new("tree" => "x")] }
    leaf = Textus::Manifest::Entry::Leaf.new(**common)
    expect { described_class.call(leaf, policy: nil) }
      .to raise_error(Textus::UsageError, /publish\.tree requires nested: true/)
  end

  it "rejects publish.tree combined with publish.to" do
    expect { validate(base.merge("publish" => [{ "tree" => "skills" }, { "to" => "x" }])) }
      .to raise_error(Textus::UsageError, /mutually exclusive/)
  end

  it "rejects template variables in publish.tree" do
    expect { validate(base.merge("publish" => [{ "tree" => "skills/{leaf}" }])) }
      .to raise_error(Textus::UsageError, /template variable|takes no template/)
  end

  it "rejects a non-string publish.tree" do
    expect { validate(base.merge("publish" => [{ "tree" => ["skills"] }])) }
      .to raise_error(Textus::UsageError, /must be a string/)
  end
end
