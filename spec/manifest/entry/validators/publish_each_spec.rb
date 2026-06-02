require "spec_helper"

# ADR 0049: publish_each shape rules moved onto the resolved mode objects
# (Publish::EachFile / Publish::EachDir) and are reached through the single
# Validators::Publish entry point, which delegates to entry.publish_mode.
RSpec.describe Textus::Manifest::Entry::Validators::Publish do
  def nested(extra)
    raw = { "key" => "working.foo", "path" => "working/foo", "zone" => "working", "nested" => true }.merge(extra)
    common = {
      raw: raw, key: raw["key"], path: raw["path"], zone: raw["zone"],
      schema: nil, owner: nil, format: "markdown", publish_to: raw["publish_to"] || []
    }
    Textus::Manifest::Entry::Nested.from_raw(common, raw)
  end

  def validate_each(publish_each:, **extra)
    described_class.call(nested({ "publish_each" => publish_each }.merge(extra)), policy: nil)
  end

  it "no-ops when publish_each is nil" do
    expect { described_class.call(nested({}), policy: nil) }.not_to raise_error
  end

  it "requires nested: true" do
    common = { raw: { "publish_each" => "{leaf}.md" }, key: "k", path: "p", zone: "working",
               schema: nil, owner: nil, format: "markdown", publish_to: [] }
    leaf = Textus::Manifest::Entry::Leaf.new(**common)
    expect { described_class.call(leaf, policy: nil) }
      .to raise_error(Textus::UsageError, /publish_each requires nested: true/)
  end

  it "is mutually exclusive with publish_to" do
    expect { validate_each(publish_each: "{leaf}.md", "publish_to" => ["../somewhere.md"]) }
      .to raise_error(Textus::UsageError, /mutually exclusive/)
  end

  it "requires a String value" do
    expect { validate_each(publish_each: 42) }
      .to raise_error(Textus::UsageError, /must be a string/)
  end

  it "rejects unknown template variables" do
    expect { validate_each(publish_each: "{leaf}-{bogus}.md") }
      .to raise_error(Textus::UsageError, /unknown template variable.+\{bogus\}/)
  end

  it "requires at least one of leaf/basename/key" do
    expect { validate_each(publish_each: "static-{ext}.md") }
      .to raise_error(Textus::UsageError, /must reference at least one of \{leaf\}, \{basename\}, or \{key\}/)
  end

  it "accepts a valid template" do
    expect { validate_each(publish_each: "agents/{basename}.md") }.not_to raise_error
  end

  context "directory-leaf entries (index_filename set)" do
    def validate_dir(publish_each:)
      validate_each(publish_each: publish_each, "index_filename" => "SKILL.md")
    end

    it "rejects {basename} (file-only) on a directory leaf" do
      expect { validate_dir(publish_each: "skills/{basename}") }
        .to raise_error(Textus::UsageError, %r{names a directory.*\{basename\}/\{ext\} are file-only})
    end

    it "rejects {ext} even alongside {leaf} on a directory leaf" do
      expect { validate_dir(publish_each: "skills/{leaf}.{ext}") }
        .to raise_error(Textus::UsageError, %r{\{basename\}/\{ext\} are file-only})
    end

    it "requires {leaf} or {key} on a directory leaf" do
      expect { validate_dir(publish_each: "skills/static") }
        .to raise_error(Textus::UsageError, /directory-leaf publish_each must reference \{leaf\} or \{key\}/)
    end

    it "accepts {key} on a directory leaf" do
      expect { validate_dir(publish_each: "skills/{key}") }.not_to raise_error
    end

    it "accepts {leaf} on a directory leaf" do
      expect { validate_dir(publish_each: "skills/{leaf}") }.not_to raise_error
    end

    it "rejects a template that names the index file (the copy-into-SKILL.md footgun)" do
      expect { validate_dir(publish_each: "skills/{leaf}/SKILL.md") }
        .to raise_error(Textus::UsageError, /must name the target DIRECTORY, not the index file/)
    end

    it "rejects a file-looking final segment with {leaf} (the copy-into-skill.md footgun)" do
      expect { validate_dir(publish_each: "skills/{leaf}.md") }
        .to raise_error(Textus::UsageError, /final segment '\{leaf\}\.md' looks like a file/)
    end

    it "rejects a literal file segment nested under {leaf}" do
      expect { validate_dir(publish_each: "skills/{leaf}/foo.md") }
        .to raise_error(Textus::UsageError, /looks like a file.*extension '\.md'/m)
    end
  end
end
