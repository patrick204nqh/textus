require "spec_helper"

RSpec.describe Textus::Dispatcher do
  it "exposes a frozen VERBS hash" do
    expect(described_class::VERBS).to be_frozen
    expect(described_class::VERBS).to be_a(Hash)
  end
end
