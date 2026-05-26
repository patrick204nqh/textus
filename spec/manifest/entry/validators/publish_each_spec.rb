require "spec_helper"

RSpec.describe Textus::Manifest::Entry::Validators::PublishEach do
  def entry_with(opts)
    instance_double(
      Textus::Manifest::Entry,
      key: "working.foo",
      publish_each: opts[:publish_each],
      nested: opts.fetch(:nested, true),
      publish_to: opts.fetch(:publish_to, []),
    )
  end

  it "no-ops when publish_each is nil" do
    expect { described_class.call(entry_with(publish_each: nil)) }.not_to raise_error
  end

  it "requires nested: true" do
    expect { described_class.call(entry_with(publish_each: "{leaf}.md", nested: false)) }
      .to raise_error(Textus::UsageError, /publish_each requires nested: true/)
  end

  it "is mutually exclusive with publish_to" do
    expect do
      described_class.call(entry_with(publish_each: "{leaf}.md", publish_to: ["../somewhere.md"]))
    end.to raise_error(Textus::UsageError, /mutually exclusive/)
  end

  it "requires a String value" do
    expect { described_class.call(entry_with(publish_each: 42)) }
      .to raise_error(Textus::UsageError, /must be a string/)
  end

  it "rejects unknown template variables" do
    expect { described_class.call(entry_with(publish_each: "{leaf}-{bogus}.md")) }
      .to raise_error(Textus::UsageError, /unknown template variable.+\{bogus\}/)
  end

  it "requires at least one of leaf/basename/key" do
    expect { described_class.call(entry_with(publish_each: "static-{ext}.md")) }
      .to raise_error(Textus::UsageError, /must reference at least one of \{leaf\}, \{basename\}, or \{key\}/)
  end

  it "accepts a valid template" do
    expect { described_class.call(entry_with(publish_each: "agents/{basename}.md")) }.not_to raise_error
  end
end
