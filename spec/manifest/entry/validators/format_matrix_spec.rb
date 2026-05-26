require "spec_helper"

RSpec.describe Textus::Manifest::Entry::Validators::FormatMatrix do
  def entry_with(opts)
    instance_double(
      Textus::Manifest::Entry,
      key: "working.foo",
      path: opts.fetch(:path, "foo.md"),
      nested: opts.fetch(:nested, false),
      format: opts.fetch(:format, "markdown"),
      schema: opts[:schema],
      template: opts[:template],
      generator: opts[:generator],
      in_generator_zone?: opts.fetch(:in_generator_zone, false),
    )
  end

  it "delegates path-extension validation to the format strategy" do
    expect do
      described_class.call(entry_with(format: "markdown", path: "foo.json", nested: false))
    end.to raise_error(Textus::UsageError, /entry 'working.foo':/)
  end

  it "rejects text + schema" do
    expect do
      described_class.call(entry_with(format: "text", path: "foo.txt", schema: "note"))
    end.to raise_error(Textus::UsageError, /text format must not declare a schema/)
  end

  it "requires template for derived markdown" do
    expect do
      described_class.call(entry_with(
                             format: "markdown", in_generator_zone: true,
                             template: nil, generator: nil, nested: false
                           ))
    end.to raise_error(Textus::UsageError, /derived markdown entries require a template/)
  end

  it "accepts derived text with template" do
    expect do
      described_class.call(entry_with(
                             format: "text", path: "x.txt", in_generator_zone: true,
                             template: "x.mustache", nested: false
                           ))
    end.not_to raise_error
  end

  it "accepts derived markdown with generator (no template)" do
    expect do
      described_class.call(entry_with(
                             format: "markdown", in_generator_zone: true,
                             template: nil, generator: { "kind" => "external" }, nested: false
                           ))
    end.not_to raise_error
  end
end
