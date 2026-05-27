require "spec_helper"

RSpec.describe Textus::Manifest::Entry::Validators::InjectIntro do
  def entry_with(opts)
    instance_double(
      Textus::Manifest::Entry::Derived,
      key: "working.foo",
      inject_intro: opts.fetch(:inject_intro, false),
      template: opts[:template],
      in_generator_zone?: opts.fetch(:in_generator_zone, true),
    )
  end

  it "no-ops when inject_intro is false" do
    expect { described_class.call(entry_with(inject_intro: false)) }.not_to raise_error
  end

  it "requires generator zone" do
    expect do
      described_class.call(entry_with(inject_intro: true, in_generator_zone: false, template: "x"))
    end.to raise_error(Textus::UsageError, /only valid on derived entries/)
  end

  it "requires a template" do
    expect do
      described_class.call(entry_with(inject_intro: true, in_generator_zone: true, template: nil))
    end.to raise_error(Textus::UsageError, /requires a template/)
  end

  it "accepts a valid configuration" do
    expect do
      described_class.call(entry_with(inject_intro: true, in_generator_zone: true, template: "claude-root.mustache"))
    end.not_to raise_error
  end
end
