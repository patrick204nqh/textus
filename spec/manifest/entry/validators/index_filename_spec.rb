require "spec_helper"

RSpec.describe Textus::Manifest::Entry::Validators::IndexFilename do
  def entry_with(opts)
    raw = { "index_filename" => opts[:index_filename] }.compact
    instance_double(
      Textus::Manifest::Entry::Nested,
      key: "working.foo",
      raw: raw,
      index_filename: opts[:index_filename],
      nested?: opts.fetch(:nested, true),
      format: opts.fetch(:format, "markdown"),
    )
  end

  it "no-ops when index_filename is nil" do
    expect { described_class.call(entry_with(index_filename: nil)) }.not_to raise_error
  end

  it "requires nested: true" do
    expect do
      described_class.call(entry_with(index_filename: "SKILL.md", nested: false))
    end.to raise_error(Textus::UsageError, /index_filename requires nested: true/)
  end

  it "rejects empty string" do
    expect do
      described_class.call(entry_with(index_filename: ""))
    end.to raise_error(Textus::UsageError, /non-empty string/)
  end

  it "rejects slashes" do
    expect do
      described_class.call(entry_with(index_filename: "dir/SKILL.md"))
    end.to raise_error(Textus::UsageError, /bare basename/)
  end

  it "rejects unknown extension" do
    expect do
      described_class.call(entry_with(index_filename: "SKILL.xyz"))
    end.to raise_error(Textus::UsageError, /unknown extension/)
  end

  it "rejects extension mismatch with format" do
    expect do
      described_class.call(entry_with(index_filename: "SKILL.json", format: "markdown"))
    end.to raise_error(Textus::UsageError, /implies format/)
  end

  it "accepts SKILL.md for markdown format" do
    expect do
      described_class.call(entry_with(index_filename: "SKILL.md", format: "markdown"))
    end.not_to raise_error
  end
end
