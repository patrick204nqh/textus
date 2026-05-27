require "spec_helper"

RSpec.describe Textus::Manifest::Entry::Validators::FormatMatrix do
  def leaf_entry(opts = {})
    instance_double(
      Textus::Manifest::Entry::Leaf,
      key: "working.foo",
      path: opts.fetch(:path, "foo.md"),
      nested?: false,
      derived?: false,
      format: opts.fetch(:format, "markdown"),
      schema: opts[:schema],
      in_generator_zone?: opts.fetch(:in_generator_zone, false),
    )
  end

  def derived_entry(opts = {})
    instance_double(
      Textus::Manifest::Entry::Derived,
      key: "working.foo",
      path: opts.fetch(:path, "foo.md"),
      nested?: false,
      derived?: true,
      format: opts.fetch(:format, "markdown"),
      schema: opts[:schema],
      template: opts[:template],
      external?: opts.fetch(:external, false),
      in_generator_zone?: opts.fetch(:in_generator_zone, false),
    )
  end

  it "delegates path-extension validation to the format strategy" do
    expect do
      described_class.call(leaf_entry(format: "markdown", path: "foo.json"))
    end.to raise_error(Textus::UsageError, /entry 'working.foo':/)
  end

  it "rejects text + schema" do
    expect do
      described_class.call(leaf_entry(format: "text", path: "foo.txt", schema: "note"))
    end.to raise_error(Textus::UsageError, /text format must not declare a schema/)
  end

  it "requires template for derived markdown" do
    expect do
      described_class.call(derived_entry(
                             format: "markdown", in_generator_zone: true,
                             template: nil, external: false
                           ))
    end.to raise_error(Textus::UsageError, /derived markdown entries require a template/)
  end

  it "accepts derived text with template" do
    expect do
      described_class.call(derived_entry(
                             format: "text", path: "x.txt", in_generator_zone: true,
                             template: "x.mustache", external: false
                           ))
    end.not_to raise_error
  end

  it "accepts derived markdown with generator (no template)" do
    expect do
      described_class.call(derived_entry(
                             format: "markdown", in_generator_zone: true,
                             template: nil, external: true
                           ))
    end.not_to raise_error
  end
end
