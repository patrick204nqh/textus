require "spec_helper"

RSpec.describe Textus::Manifest::Entry::Validators::InjectBoot do
  def entry_with(opts)
    instance_double(
      Textus::Manifest::Entry::Derived,
      key: "working.foo",
      inject_boot: opts.fetch(:inject_boot, false),
      template: opts[:template],
      derived?: opts.fetch(:derived, true),
    )
  end

  it "no-ops when inject_boot is false" do
    expect { described_class.call(entry_with(inject_boot: false), policy: nil) }.not_to raise_error
  end

  it "requires derived entry" do
    expect do
      described_class.call(entry_with(inject_boot: true, derived: false, template: "x"), policy: nil)
    end.to raise_error(Textus::UsageError, /only valid on derived entries/)
  end

  it "requires a template" do
    expect do
      described_class.call(entry_with(inject_boot: true, derived: true, template: nil), policy: nil)
    end.to raise_error(Textus::UsageError, /requires a template/)
  end

  it "accepts a valid configuration" do
    expect do
      described_class.call(entry_with(inject_boot: true, derived: true, template: "claude-root.mustache"), policy: nil)
    end.not_to raise_error
  end
end
