require "spec_helper"

RSpec.describe Textus::Dispatcher do
  it "exposes a frozen VERBS hash" do
    expect(described_class::VERBS).to be_frozen
    expect(described_class::VERBS).to be_a(Hash)
  end

  it "maps every verb registered with Application::UseCase to a callable class" do
    # During Phase 3 the two coexist. Once Phase 7 lands, UseCase is gone.
    Textus::Application::UseCase.entries.each do |entry|
      expect(described_class::VERBS).to have_key(entry.verb), "missing verb #{entry.verb}"
      mapped = described_class::VERBS[entry.verb]
      # Either the pre-collapse module (still in use) or its post-collapse class
      # is acceptable here; both define a callable entrypoint.
      expect(mapped).to be_a(Module)
      expect(mapped).to respond_to(:new).or respond_to(:call)
    end
  end
end
