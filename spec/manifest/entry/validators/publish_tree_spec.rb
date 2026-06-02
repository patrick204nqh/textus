require "spec_helper"

RSpec.describe Textus::Manifest::Entry::Validators::PublishTree do
  def entry(raw)
    common = {
      raw: raw, key: raw["key"], path: raw["path"], zone: raw["zone"],
      schema: nil, owner: nil, format: "markdown",
      publish_to: raw["publish_to"] || []
    }
    Textus::Manifest::Entry::Nested.from_raw(common, raw)
  end

  def validate(raw) = described_class.call(entry(raw), policy: nil)

  let(:base) do
    { "key" => "working.skills", "path" => "working/skills", "zone" => "working", "nested" => true }
  end

  it "passes a well-formed publish_tree entry" do
    expect { validate(base.merge("publish_tree" => "skills")) }.not_to raise_error
  end

  it "is a no-op when publish_tree is absent" do
    expect { validate(base.merge("publish_each" => "skills/{leaf}")) }.not_to raise_error
  end

  it "rejects publish_tree on a non-nested entry" do
    common = { raw: { "publish_tree" => "x" }, key: "k", path: "p", zone: "working",
               schema: nil, owner: nil, format: "markdown", publish_to: [] }
    leaf = Textus::Manifest::Entry::Leaf.new(**common)
    expect { described_class.call(leaf, policy: nil) }
      .to raise_error(Textus::UsageError, /requires nested: true/)
  end

  it "rejects publish_tree combined with publish_to" do
    expect { validate(base.merge("publish_tree" => "skills", "publish_to" => ["x"])) }
      .to raise_error(Textus::UsageError, /mutually exclusive/)
  end

  it "rejects publish_tree combined with publish_each" do
    expect { validate(base.merge("publish_tree" => "skills", "publish_each" => "skills/{leaf}")) }
      .to raise_error(Textus::UsageError, /mutually exclusive/)
  end

  it "rejects template variables in publish_tree" do
    expect { validate(base.merge("publish_tree" => "skills/{leaf}")) }
      .to raise_error(Textus::UsageError, /template variable/)
  end

  it "rejects publish_tree combined with index_filename" do
    expect { validate(base.merge("publish_tree" => "skills", "index_filename" => "SKILL.md")) }
      .to raise_error(Textus::UsageError, /index_filename/)
  end

  it "rejects a non-string publish_tree" do
    expect { validate(base.merge("publish_tree" => ["skills"])) }
      .to raise_error(Textus::UsageError, /must be a string/)
  end
end
