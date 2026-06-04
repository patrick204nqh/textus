require "spec_helper"

RSpec.describe Textus::Manifest::Entry::Validators::Ignore do
  def entry_with(ignore:, nested: true)
    raw = { "ignore" => ignore }.compact
    instance_double(
      Textus::Manifest::Entry::Nested,
      key: "skills",
      raw: raw,
      nested?: nested,
    )
  end

  it "no-ops when ignore is absent" do
    expect { described_class.call(entry_with(ignore: nil)) }.not_to raise_error
  end

  it "accepts a list of non-empty strings" do
    expect { described_class.call(entry_with(ignore: ["**/node_modules/**", "**/dist/**"])) }.not_to raise_error
  end

  it "rejects ignore on a non-nested entry" do
    expect do
      described_class.call(entry_with(ignore: ["**/x/**"], nested: false))
    end.to raise_error(Textus::UsageError, /ignore requires nested: true/)
  end

  it "rejects a non-list ignore" do
    expect do
      described_class.call(entry_with(ignore: "**/x/**"))
    end.to raise_error(Textus::UsageError, /ignore must be a list/)
  end

  it "rejects an empty-string pattern" do
    expect do
      described_class.call(entry_with(ignore: ["**/x/**", ""]))
    end.to raise_error(Textus::UsageError, /non-empty string/)
  end
end
