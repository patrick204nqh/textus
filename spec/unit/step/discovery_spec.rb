# spec/unit/step/discovery_spec.rb
require "spec_helper"

RSpec.describe Textus::Step::Discovery do
  it "derives kind from the parent dir and name from the basename" do
    d = described_class.parse("/repo/.textus/steps/fetch/authority.rb", base: "/repo/.textus/steps")
    expect(d.kind).to eq(:fetch)
    expect(d.name).to eq(:authority)
  end

  it "preserves hyphenated names" do
    d = described_class.parse("/repo/.textus/steps/fetch/markdown-links.rb", base: "/repo/.textus/steps")
    expect(d.name).to eq(:"markdown-links")
  end

  it "rejects an unknown kind directory" do
    expect { described_class.parse("/repo/.textus/steps/bogus/x.rb", base: "/repo/.textus/steps") }
      .to raise_error(Textus::UsageError, /unknown step kind 'bogus'/)
  end

  it "rejects a file directly under steps/ (no kind dir)" do
    expect { described_class.parse("/repo/.textus/steps/loose.rb", base: "/repo/.textus/steps") }
      .to raise_error(Textus::UsageError, %r{must live under steps/<kind>/})
  end
end
