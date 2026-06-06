require "spec_helper"

RSpec.describe Textus::Manifest::Schema do
  it "registers retention, not upkeep" do
    expect(described_class::FIELD_REGISTRY.keys).to include(:retention)
    expect(described_class::FIELD_REGISTRY.keys).not_to include(:upkeep)
  end

  it "RULE_KEYS includes retention and excludes upkeep" do
    expect(described_class::RULE_KEYS).to include("retention")
    expect(described_class::RULE_KEYS).not_to include("upkeep")
  end

  it "ENTRY_KEYS includes source and excludes compute/template/intake" do
    expect(described_class::ENTRY_KEYS).to include("source")
    expect(described_class::ENTRY_KEYS).not_to include("compute", "template", "intake")
  end
end
